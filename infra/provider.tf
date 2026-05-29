terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
  required_version = ">= 1.6.0"
}

provider "aws" {
  region = "us-west-2"
}

# aws_eks_cluster_auth generates a short-lived token (15 min) — Terraform
# refreshes it automatically on each plan/apply so credentials never expire.
data "aws_eks_cluster_auth" "this" {
  name = module.compute_eks.cluster_name
}

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
