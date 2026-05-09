# Session 3 — Demo D: EKS Cluster + Same API on Kubernetes

Deploy the same Go HTTP API from Demo C onto an EKS cluster using Terraform to provision the cluster and `kubectl` to apply the Kubernetes manifests.

## What students learn

- How a single Go binary runs unchanged across EC2, Lambda, ECS, and EKS — only the environment variable injection method changes (`COMPUTE_TYPE` comes from a ConfigMap here)
- Why `aws eks update-kubeconfig` is required after every EKS `terraform apply` — without it `kubectl` fails with no context or connection refused
- How `enable_cluster_creator_admin_permissions = true` prevents a silent 403 after the cluster is up
- Why `ami_type` must match the instance family — `AL2023_ARM_64_STANDARD` for `t4g.*` nodes; mismatching causes nodes to fail joining
- Why `node_security_group_additional_rules` must open NodePort range 30000–32767 — the in-tree cloud controller provisions the NLB but does not patch the node security group, so health checks hang without it
- How Terraform and Kubernetes manifests form two distinct automation layers: Terraform provisions the platform, manifests deploy the application

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
│   └── service.yaml     # LoadBalancer type — provisions an NLB
├── infra/
│   ├── main.tf          # calls modules/compute_eks
│   ├── variables.tf
│   ├── outputs.tf       # exports cluster_name, endpoint, CA data
│   ├── provider.tf
│   ├── envs/dev/
│   │   └── dev.tfvars
│   └── modules/
│       └── compute_eks/
│           ├── main.tf      # terraform-aws-modules/eks/aws ~> 20.0
│           ├── variables.tf
│           └── outputs.tf
└── .github/workflows/
    └── deploy.yml       # build-and-deploy → terraform → k8s
```

## Prerequisites

- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) — configured with credentials for the target account
- [Terraform >= 1.6](https://developer.hashicorp.com/terraform/install)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

> The EKS cluster takes 15+ minutes to provision. For this demo the cluster is pre-provisioned — you start from a running cluster.

## Demo workflow

### 1. Connect kubectl to the cluster

From the `infra/` directory, read the cluster name from Terraform outputs and update your local kubeconfig.

```bash
cd infra

CLUSTER_NAME=$(terraform output -raw cluster_name)

aws eks update-kubeconfig \
  --region us-west-2 \
  --name ${CLUSTER_NAME}
```

Expected output:

```
Updated context arn:aws:eks:us-west-2:<account>:cluster/dev-demo-eks in /Users/you/.kube/config
```

### 2. Verify nodes

```bash
kubectl get nodes -o wide
```

Expected output:

```
NAME                         STATUS   ROLES    AGE   VERSION
ip-10-0-1-xx.ec2.internal    Ready    <none>   10m   v1.35.x
ip-10-0-2-xx.ec2.internal    Ready    <none>   10m   v1.35.x
```

Screenshot this output — save it as `evidence/eks-nodes.png` for D2 §3.5.

### 3. Apply Kubernetes manifests

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

### 4. Wait for pods to be Running

```bash
kubectl get pods -n demo-app -w
```

Wait until all pods show `Running` (about 20 seconds), then `Ctrl-C`.

### 5. Wait for the NLB endpoint

The `EXTERNAL-IP` field starts as `<pending>` while AWS provisions the Network Load Balancer (~60 seconds).

```bash
kubectl get svc demo-app -n demo-app -w
```

Expected output (once ready):

```
NAME       TYPE           CLUSTER-IP      EXTERNAL-IP                                   PORT(S)
demo-app   LoadBalancer   172.20.x.x      abc123.elb.us-west-2.amazonaws.com            80:xxxxx/TCP
```

Grab the hostname:

```bash
NLB_HOSTNAME=$(kubectl get svc demo-app -n demo-app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo ${NLB_HOSTNAME}
```

### 6. Verify the deployment

```bash
curl http://${NLB_HOSTNAME}/health
```

Expected output:

```json
{"compute":"eks","status":"ok"}
```

```bash
curl -X POST http://${NLB_HOSTNAME}/echo \
  -H "Content-Type: application/json" -d '{"message":"hello"}'
```

Expected output:

```json
{"compute":"eks","message":"hello"}
```

### 7. Clean up

```bash
cd infra
terraform destroy -var-file=envs/dev/dev.tfvars
```

> Teardown takes 10–15 minutes. Do not run this during the session.

## Expected outcomes

By the end of this demo, you should be able to:

1. Explain why `aws eks update-kubeconfig` must be run after provisioning an EKS cluster
2. Read a Kubernetes ConfigMap and trace how `COMPUTE_TYPE=eks` reaches the running container via `envFrom`
3. Describe why `ami_type = "AL2023_ARM_64_STANDARD"` must match the `t4g.*` instance family
4. Explain what happens to NLB health checks if the NodePort security group rule is missing
5. Distinguish Terraform's role (cluster infrastructure) from `kubectl`'s role (application deployment) — two separate, reproducible automation layers
