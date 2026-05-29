# Session 6 — Demo 4: EKS Cluster + ALB Controller + Kubernetes Ingress

Extend an existing EKS deployment with the AWS Load Balancer Controller — replacing the legacy in-tree NLB with an Application Load Balancer provisioned via a Kubernetes `Ingress` object managed entirely by Terraform.

> **Forked from:** [`ugalileo-pdds-oyd-2026/session-3-demo-4-eks`](https://github.com/ugalileo-pdds-oyd-2026/session-3-demo-4-eks) — the Session 3 EKS demo that this demo extends.

## What students learn

- Why EKS has no built-in way to create an ALB — the AWS Load Balancer Controller is a separate component that watches `Ingress` objects and provisions ALBs on your behalf
- How IRSA (IAM Roles for Service Accounts) scopes an IAM role to a single Kubernetes ServiceAccount using a `StringEquals` condition on the OIDC provider — no static credentials required
- Why the upstream EKS Terraform module already configures IRSA by default — `enable_irsa` defaults to `true` in v20, and `oidc_provider_arn` / `cluster_oidc_issuer_url` are free outputs
- How the `helm` provider installs the ALB controller and the `kubernetes` provider creates the `Ingress` object in the same `terraform apply` — one source of truth for both AWS and Kubernetes resources
- Why `depends_on = [helm_release.alb_controller]` on the `Ingress` resource is required — without it the Ingress object would exist but the controller would not yet be watching for it
- Why switching the Service from `LoadBalancer` to `ClusterIP` avoids a redundant NLB alongside the ALB — `ClusterIP` exposes the Service inside the cluster only, and all external traffic enters through the ALB

## Project structure

```
.
├── app/
│   ├── main.go          # HTTP handler — reads COMPUTE_TYPE from env
│   ├── server.go        # HTTP server entrypoint
│   ├── lambda.go        # Lambda entrypoint (unused here)
│   ├── Dockerfile       # linux/arm64 image
│   ├── go.mod
│   └── go.sum
├── k8s/
│   ├── namespace.yaml   # demo-app namespace
│   ├── configmap.yaml   # injects COMPUTE_TYPE=eks via envFrom
│   ├── deployment.yaml  # 2 replicas, pulls ECR image
│   └── service.yaml     # ClusterIP — external traffic enters via the ALB Ingress
├── infra/
│   ├── main.tf          # calls compute_eks and alb_controller modules
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf      # aws + kubernetes + helm providers
│   ├── envs/dev/
│   │   └── dev.tfvars
│   └── modules/
│       ├── compute_eks/
│       │   ├── main.tf      # terraform-aws-modules/eks/aws ~> 20.0
│       │   ├── variables.tf
│       │   └── outputs.tf   # exports oidc_provider_arn, cluster_oidc_issuer_url
│       └── alb_controller/
│           ├── main.tf      # IRSA role, Helm release, kubernetes_ingress_v1
│           ├── variables.tf
│           ├── outputs.tf
│           └── iam_policy.json  # vendored from aws-load-balancer-controller v2.17.1
└── .github/workflows/
    └── deploy.yml       # build-and-deploy → terraform → k8s
```

## Prerequisites

- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) — configured with credentials for the target account
- [Terraform >= 1.6](https://developer.hashicorp.com/terraform/install)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)

> The EKS cluster takes 15+ minutes to provision. For this demo the cluster is pre-provisioned — you start from a running cluster.

## Demo workflow

### 1. Review the compute_eks module outputs

Open `infra/modules/compute_eks/outputs.tf`. The upstream EKS Terraform module (`terraform-aws-modules/eks/aws ~> 20.0`) enables IRSA by default — the module already configures the OIDC provider and exposes it as outputs:

```hcl
output "oidc_provider_arn" { ... }
output "cluster_oidc_issuer_url" { ... }
```

These two outputs are everything the ALB controller needs to authenticate to AWS — no extra cluster configuration required.

### 2. Review the kubernetes and helm providers

Open `infra/provider.tf`. Two new providers were added alongside the existing `aws` provider:

```hcl
provider "kubernetes" {
  host                   = module.compute_eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.compute_eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.compute_eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.compute_eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
```

Both providers use `aws_eks_cluster_auth` to generate a short-lived token (15 min). Terraform refreshes it automatically on each plan/apply.

### 3. Review the alb_controller module

Open `infra/modules/alb_controller/main.tf`. The module contains three logical sections:

**IRSA role trust policy** — the `StringEquals` condition on `system:serviceaccount:kube-system:aws-load-balancer-controller` scopes the role so only that specific ServiceAccount can assume it. No other pod in the cluster can use it:

```hcl
condition {
  test     = "StringEquals"
  variable = "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub"
  values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
}
```

**Helm release** — installs the controller chart from `eks-charts`. The `serviceAccount.annotations.eks.amazonaws.com/role-arn` annotation is how IRSA works: the controller pod reads this annotation, exchanges it for temporary AWS credentials via the OIDC provider, and uses those credentials to create ALBs.

**kubernetes_ingress_v1** — three annotations drive the ALB controller behavior:
- `kubernetes.io/ingress.class: alb` — selects this controller over others
- `alb.ingress.kubernetes.io/scheme: internet-facing` — creates a public ALB
- `alb.ingress.kubernetes.io/target-type: ip` — routes directly to pod IPs, skipping the NodePort hop

Note the `depends_on = [helm_release.alb_controller]` on the Ingress resource — this ensures the controller is fully running before Terraform creates the Ingress object.

### 4. Review the Service type change

Open `k8s/service.yaml`. The Service was changed from `LoadBalancer` to `ClusterIP`:

```yaml
spec:
  selector:
    app: demo-app
  ports:
    - port: 80
      targetPort: 8080
  type: ClusterIP
```

Keeping `type: LoadBalancer` after adding the Ingress would cause the in-tree cloud controller to provision an NLB alongside the ALB — a redundant load balancer that adds cost for no benefit.

### 5. Review how the root module wires the alb_controller

Open `infra/main.tf`. The `alb_controller` module receives its inputs directly from `compute_eks` outputs — no manual copying of IDs:

```hcl
module "alb_controller" {
  source = "./modules/alb_controller"

  cluster_name            = module.compute_eks.cluster_name
  oidc_provider_arn       = module.compute_eks.oidc_provider_arn
  cluster_oidc_issuer_url = module.compute_eks.cluster_oidc_issuer_url
  vpc_id                  = var.vpc_id
  region                  = "us-west-2"

  app_service_name = "demo-app"
  app_service_port = 80
  app_namespace    = "demo-app"
}
```

### 6. Validate the Terraform configuration

```bash
cd infra
terraform fmt -check -recursive
terraform init -upgrade -backend=false
terraform validate
```

Expected output:

```
Success! The configuration is valid.
```

> `init -backend=false` + `validate` proves all HCL references resolve correctly without requiring a live cluster. `plan` and `apply` do require a running cluster because the `helm` and `kubernetes` providers authenticate against it.

### 7. Connect kubectl to the cluster

From the `infra/` directory, read the cluster name from Terraform outputs and update your local kubeconfig:

```bash
CLUSTER_NAME=$(terraform output -raw cluster_name)

aws eks update-kubeconfig \
  --region us-west-2 \
  --name ${CLUSTER_NAME}
```

Expected output:

```
Updated context arn:aws:eks:us-west-2:<account>:cluster/dev-demo-eks in /Users/you/.kube/config
```

### 8. Verify nodes

```bash
kubectl get nodes -o wide
```

Expected output:

```
NAME                         STATUS   ROLES    AGE   VERSION
ip-10-0-1-xx.ec2.internal    Ready    <none>   10m   v1.35.x
ip-10-0-2-xx.ec2.internal    Ready    <none>   10m   v1.35.x
```

### 9. Apply Kubernetes manifests

From the repo root:

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
```

Expected output:

```
namespace/demo-app created
configmap/app-config created
deployment.apps/demo-app created
service/demo-app created
```

### 10. Wait for pods to be Running

```bash
kubectl get pods -n demo-app -w
```

Wait until all pods show `Running` (about 20 seconds), then `Ctrl-C`.

### 11. Apply Terraform to install the ALB controller and create the Ingress

```bash
cd infra
terraform apply -var-file=envs/dev/dev.tfvars
```

Expected output (once complete):

```
Apply complete! Resources: X added, 0 changed, 0 destroyed.
```

### 12. Wait for the ALB endpoint

The Ingress `ADDRESS` field starts empty while AWS provisions the Application Load Balancer (~60–90 seconds):

```bash
kubectl get ingress app-ingress -n demo-app -w
```

Once the ALB is ready, the `ADDRESS` column populates with the ALB hostname. Grab it:

```bash
ALB_HOSTNAME=$(kubectl get ingress app-ingress -n demo-app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo ${ALB_HOSTNAME}
```

### 13. Verify the deployment

```bash
curl http://${ALB_HOSTNAME}/health
```

Expected output:

```json
{"compute":"eks","status":"ok"}
```

```bash
curl -X POST http://${ALB_HOSTNAME}/echo \
  -H "Content-Type: application/json" -d '{"message":"hello"}'
```

Expected output:

```json
{"compute":"eks","message":"hello"}
```

### 14. Clean up

```bash
cd infra
terraform destroy -var-file=envs/dev/dev.tfvars
```

> Teardown takes 10–15 minutes. Do not run this during the session.

## Troubleshooting

**Ingress ADDRESS stays empty** — The ALB controller authenticates to AWS via IRSA (`AssumeRoleWithWebIdentity`). If STS is disabled for the `us-west-2` regional endpoint, the controller cannot provision the ALB. Fix: IAM Console → Account settings → Security Token Service (STS) → activate the `us-west-2` endpoint. The controller retries automatically once active.

## Expected outcomes

By the end of this demo, students should be able to:

1. Explain why EKS needs the AWS Load Balancer Controller to create an ALB — the controller watches `Ingress` objects; the cluster alone has no mechanism for it
2. Trace how IRSA works end-to-end: OIDC provider → trust policy `StringEquals` condition → ServiceAccount annotation → temporary AWS credentials in the pod
3. Explain why `depends_on` on the `kubernetes_ingress_v1` resource is required and what breaks without it
4. Explain why changing the Service type from `LoadBalancer` to `ClusterIP` prevents a redundant NLB from being provisioned
5. Describe what Terraform manages (IAM role, Helm release, Ingress object) versus what `kubectl` manages (namespace, ConfigMap, Deployment, Service) — and why both layers are needed
