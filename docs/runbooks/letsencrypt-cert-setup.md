# Let's Encrypt Certificate Setup via cert-manager

**Purpose**: Replace the default self-signed ingress certificate with a trusted Let's Encrypt wildcard certificate using cert-manager and DNS-01 validation via Route 53.

**When to use**: After a successful OKD deployment, when the cluster is fully operational and all ClusterOperators are Available.

**ADR**: [013-letsencrypt-certificate-automation](../adrs/013-letsencrypt-certificate-automation.md)

---

## Prerequisites

- OKD cluster is installed and all ClusterOperators are Available
- `oc` CLI is configured with kubeadmin credentials:
  ```bash
  export KUBECONFIG=/root/okd-metal-installer/ignition-output/auth/kubeconfig
  ```
- AWS credentials with Route 53 permissions (same credentials used for DNS setup)
- Route 53 hosted zone ID (from `inventory/sno-prod/group_vars/all.yml`: `Z04957801CD6ZAE7L5S0E`)

## Step 1: Install cert-manager Operator

Install from OperatorHub via the CLI:

```bash
oc apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager-operator
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: cert-manager-operator
  namespace: cert-manager-operator
spec:
  targetNamespaces:
  - cert-manager-operator
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-cert-manager-operator
  namespace: cert-manager-operator
spec:
  channel: stable-v1
  name: openshift-cert-manager-operator
  source: community-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF
```

Wait for the operator to install:

```bash
oc wait --for=condition=Available deployment/cert-manager \
  -n cert-manager --timeout=180s

oc wait --for=condition=Available deployment/cert-manager-webhook \
  -n cert-manager --timeout=180s
```

Verify the cert-manager pods are running:

```bash
oc get pods -n cert-manager
```

Expected output: `cert-manager`, `cert-manager-cainjector`, and `cert-manager-webhook` pods all Running.

## Step 2: Create AWS Credentials Secret

Create a Secret with Route 53 access credentials in the `cert-manager` namespace:

```bash
oc create secret generic aws-route53-credentials \
  -n cert-manager \
  --from-literal=access-key-id='YOUR_AWS_ACCESS_KEY_ID' \
  --from-literal=secret-access-key='YOUR_AWS_SECRET_ACCESS_KEY'
```

Replace `YOUR_AWS_ACCESS_KEY_ID` and `YOUR_AWS_SECRET_ACCESS_KEY` with the actual values from the Ansible vault:

```bash
ansible-vault view inventory/sno-prod/vault.yml --vault-password-file=.vault_password
```

## Step 3: Create ClusterIssuer

First, test with Let's Encrypt **staging** to avoid rate limits:

```bash
oc apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: admin@ocpincubator.com
    privateKeySecretRef:
      name: letsencrypt-staging-key
    solvers:
    - dns01:
        route53:
          region: eu-central-1
          hostedZoneID: Z04957801CD6ZAE7L5S0E
          accessKeyIDSecretRef:
            name: aws-route53-credentials
            key: access-key-id
          secretAccessKeySecretRef:
            name: aws-route53-credentials
            key: secret-access-key
EOF
```

Verify the ClusterIssuer is ready:

```bash
oc get clusterissuer letsencrypt-staging -o wide
```

Expected: `READY = True`.

## Step 4: Request a Staging Certificate (Test)

```bash
oc apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: apps-wildcard-staging
  namespace: openshift-ingress
spec:
  secretName: apps-wildcard-tls-staging
  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer
  dnsNames:
  - "*.apps.okd-sno.ocpincubator.com"
EOF
```

Monitor the certificate request:

```bash
oc get certificate apps-wildcard-staging -n openshift-ingress -w
```

Wait for `READY = True`. This may take 1-3 minutes for DNS propagation.

If it fails, check the challenge and order status:

```bash
oc get challenges -n openshift-ingress
oc describe certificate apps-wildcard-staging -n openshift-ingress
```

## Step 5: Switch to Production and Issue Real Certificate

Once staging works, create the production ClusterIssuer:

```bash
oc apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@ocpincubator.com
    privateKeySecretRef:
      name: letsencrypt-production-key
    solvers:
    - dns01:
        route53:
          region: eu-central-1
          hostedZoneID: Z04957801CD6ZAE7L5S0E
          accessKeyIDSecretRef:
            name: aws-route53-credentials
            key: access-key-id
          secretAccessKeySecretRef:
            name: aws-route53-credentials
            key: secret-access-key
EOF
```

Issue the production certificate:

```bash
oc apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: apps-wildcard
  namespace: openshift-ingress
spec:
  secretName: apps-wildcard-tls
  issuerRef:
    name: letsencrypt-production
    kind: ClusterIssuer
  dnsNames:
  - "*.apps.okd-sno.ocpincubator.com"
EOF
```

Wait for it to be ready:

```bash
oc get certificate apps-wildcard -n openshift-ingress -w
```

## Step 6: Patch the IngressController

Tell the default IngressController to use the new certificate:

```bash
oc patch ingresscontroller default \
  -n openshift-ingress-operator \
  --type=merge \
  -p '{"spec":{"defaultCertificate":{"name":"apps-wildcard-tls"}}}'
```

The router pods will restart automatically. Wait for them:

```bash
oc rollout status deployment/router-default -n openshift-ingress --timeout=120s
```

## Step 7: Verify

Test the console with curl (should no longer show self-signed certificate errors):

```bash
curl -sI https://console-openshift-console.apps.okd-sno.ocpincubator.com | head -5
```

Check the certificate details:

```bash
echo | openssl s_client -connect console-openshift-console.apps.okd-sno.ocpincubator.com:443 -servername console-openshift-console.apps.okd-sno.ocpincubator.com 2>/dev/null | openssl x509 -noout -issuer -dates -subject
```

Expected issuer: `O = Let's Encrypt` (or `(STAGING) Let's Encrypt` if still on staging).

Access the web console in a browser -- no security warnings should appear:

```
https://console-openshift-console.apps.okd-sno.ocpincubator.com
```

## Step 8: Clean Up Staging Resources (Optional)

```bash
oc delete certificate apps-wildcard-staging -n openshift-ingress
oc delete secret apps-wildcard-tls-staging -n openshift-ingress
oc delete clusterissuer letsencrypt-staging
```

## Renewal

cert-manager automatically renews certificates before they expire (default: 30 days before the 90-day expiry). No manual intervention is needed.

To check renewal status:

```bash
oc get certificate apps-wildcard -n openshift-ingress -o jsonpath='{.status.renewalTime}'
```

## Troubleshooting

### Challenge stuck in pending

```bash
oc get challenges -A
oc describe challenge <name> -n openshift-ingress
```

Common causes:
- AWS credentials Secret not in `cert-manager` namespace
- IAM permissions insufficient for Route 53 `ChangeResourceRecordSets`
- Wrong `hostedZoneID`

### Certificate not becoming Ready

```bash
oc get certificaterequest -n openshift-ingress
oc describe certificaterequest <name> -n openshift-ingress
oc logs deployment/cert-manager -n cert-manager --tail=50
```

### Router pods not restarting after IngressController patch

```bash
oc get pods -n openshift-ingress
oc rollout restart deployment/router-default -n openshift-ingress
```

## Optional: API Server Certificate

To replace the API server certificate (more involved, affects `oc login`):

```bash
oc apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: api-cert
  namespace: openshift-config
spec:
  secretName: api-tls
  issuerRef:
    name: letsencrypt-production
    kind: ClusterIssuer
  dnsNames:
  - "api.okd-sno.ocpincubator.com"
EOF
```

Then patch the API server:

```bash
oc patch apiserver cluster \
  --type=merge \
  -p '{"spec":{"servingCerts":{"namedCertificates":[{"names":["api.okd-sno.ocpincubator.com"],"servingCertificate":{"name":"api-tls"}}]}}}'
```

**Warning**: This triggers a kube-apiserver rollout. The API will be temporarily unavailable (1-2 minutes on SNO). Plan accordingly.
