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

module "alb_controller" {
  source = "./modules/alb_controller"

  cluster_name            = module.compute_eks.cluster_name
  oidc_provider_arn       = module.compute_eks.oidc_provider_arn
  cluster_oidc_issuer_url = module.compute_eks.cluster_oidc_issuer_url
  vpc_id                  = var.vpc_id
  region                  = "us-west-2"

  # Values come from k8s/service.yaml
  app_service_name = "demo-app"
  app_service_port = 80
  app_namespace    = "demo-app"
}
