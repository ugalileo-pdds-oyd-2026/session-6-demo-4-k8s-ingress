output "cluster_endpoint" {
  description = "API server endpoint — used to build kubeconfig"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA certificate — used to build kubeconfig"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_name" {
  description = "Cluster name — pass to aws eks update-kubeconfig"
  value       = module.eks.cluster_name
}