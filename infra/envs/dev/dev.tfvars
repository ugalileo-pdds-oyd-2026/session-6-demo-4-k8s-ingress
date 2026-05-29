cluster_name       = "dev-demo-eks"
cluster_version    = "1.35"
vpc_id             = "vpc-2e760856"
subnet_ids         = ["subnet-a88843d0", "subnet-f927d2b3"]
node_instance_type = "t4g.small"
desired_size       = 2
min_size           = 1
max_size           = 3
