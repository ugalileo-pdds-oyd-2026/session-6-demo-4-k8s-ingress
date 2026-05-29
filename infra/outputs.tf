output "cluster_endpoint" {
  description = "API server endpoint — used to build kubeconfig"
  value       = module.compute_eks.cluster_endpoint
}

output "cluster_name" {
  description = "Cluster name — pass to aws eks update-kubeconfig"
  value       = module.compute_eks.cluster_name
}

output "alb_controller_role_arn" {
  description = "ARN of the IRSA IAM role assumed by the AWS Load Balancer Controller"
  value       = module.alb_controller.alb_controller_role_arn
}
