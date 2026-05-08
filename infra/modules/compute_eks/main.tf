module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  cluster_endpoint_public_access = true

  # Grants the IAM principal that creates the cluster admin access via the
  # EKS access entry API. Without this, the creator has no kubectl permissions
  # even though they provisioned the cluster — update-kubeconfig succeeds but
  # every kubectl command returns Unauthorized.
  enable_cluster_creator_admin_permissions = true

  # Opt out of EKS extended support — avoids per-cluster hourly charge after
  # standard support window ends. Standard support is free; extended support is not.
  cluster_upgrade_policy = {
    support_type = "STANDARD"
  }

  # Allow inbound traffic on the NodePort range from the NLB (in-tree controller
  # does not patch the node SG automatically — without this the NLB health checks
  # fail and requests hang).
  node_security_group_additional_rules = {
    ingress_nlb_nodeport = {
      description = "NLB to NodePort range"
      protocol    = "tcp"
      from_port   = 30000
      to_port     = 32767
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      ami_type       = "AL2023_ARM_64_STANDARD" # arm64 AMI — required for t4g instances
      min_size       = var.min_size
      max_size       = var.max_size
      desired_size   = var.desired_size
    }
  }
}
