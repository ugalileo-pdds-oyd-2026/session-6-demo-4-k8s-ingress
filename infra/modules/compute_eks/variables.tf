variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane (e.g. '1.35')"
  type        = string
  default     = "1.35"
}

variable "vpc_id" {
  description = "VPC ID where the cluster control plane and nodes will run"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for control plane and node group — min 2, multi-AZ"
  type        = list(string)
}

variable "node_instance_type" {
  description = "EC2 instance type for the managed node group — must be arm64 (t4g.*)"
  type        = string
  default     = "t4g.micro"
  # t4g.nano (512 MB) is too constrained for system pods (kube-proxy, aws-node, coredns)
  # t4g.micro (1 GB) is technically sufficient but often OOMs under load
  # t4g.small (2 GB) is the practical minimum for a functional EKS node
}

variable "desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 3
}