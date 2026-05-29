variable "cluster_name" {
  description = "Name of the EKS cluster — used to name the IRSA IAM role and Helm values"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider attached to the EKS cluster — used in the IAM trust policy"
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster — used to scope the IAM trust condition"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the EKS cluster runs — passed to the ALB controller Helm chart"
  type        = string
}

variable "region" {
  description = "AWS region where the EKS cluster runs — passed to the ALB controller Helm chart"
  type        = string
  default     = "us-west-2"
}

variable "app_service_name" {
  description = "Kubernetes Service name to route Ingress traffic to — must match k8s/service.yaml"
  type        = string
}

variable "app_service_port" {
  description = "Port exposed by the Kubernetes Service — must match k8s/service.yaml"
  type        = number
}

variable "app_namespace" {
  description = "Kubernetes namespace where the app Service lives — must match k8s/service.yaml"
  type        = string
}
