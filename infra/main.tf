module "compute_eks" {
  source = "./modules/compute_eks"

  cluster_name       = var.cluster_name
  cluster_version    = var.cluster_version
  vpc_id             = var.vpc_id
  subnet_ids         = var.subnet_ids
  node_instance_type = var.node_instance_type
  desired_size       = var.desired_size
  min_size           = var.min_size
  max_size           = var.max_size
}
