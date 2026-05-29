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

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider — used to create IRSA IAM role trust policies"
  value       = module.eks.oidc_provider_arn
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL — used to scope IRSA trust conditions"
  value       = module.eks.cluster_oidc_issuer_url
}
