output "alb_controller_role_arn" {
  description = "ARN of the IRSA IAM role assumed by the ALB controller ServiceAccount"
  value       = aws_iam_role.alb_controller.arn
}

output "ingress_name" {
  description = "Name of the kubernetes_ingress_v1 resource created for the app"
  value       = kubernetes_ingress_v1.app.metadata[0].name
}
