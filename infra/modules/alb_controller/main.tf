# ---------------------------------------------------------------------------
# IRSA role for the AWS Load Balancer Controller
# ---------------------------------------------------------------------------
# The trust policy allows the controller's ServiceAccount (in kube-system)
# to assume this role via the cluster's OIDC provider.

data "aws_iam_policy_document" "alb_controller_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${var.cluster_name}-alb-controller"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume.json
}

# Permissions policy vendored from kubernetes-sigs/aws-load-balancer-controller
# docs/install/iam_policy.json @ v2.17.1. Grants the controller rights to
# provision ALBs, target groups, listeners, security groups, and attach ACM
# certs and WAF ACLs on behalf of Kubernetes Ingress objects.
resource "aws_iam_policy" "alb_controller" {
  name   = "${var.cluster_name}-alb-controller"
  policy = file("${path.module}/iam_policy.json")
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

# ---------------------------------------------------------------------------
# Helm release — AWS Load Balancer Controller
# ---------------------------------------------------------------------------
# Installs the controller into kube-system and wires the IRSA annotation so
# the controller's ServiceAccount can call AWS APIs (create/update ALBs).

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.alb_controller.arn
  }
  set {
    name  = "region"
    value = var.region
  }
  set {
    name  = "vpcId"
    value = var.vpc_id
  }
}

# ---------------------------------------------------------------------------
# Kubernetes Ingress — routes public ALB traffic to the app Service
# ---------------------------------------------------------------------------
# The "alb" ingress class annotation triggers the controller to provision an
# internet-facing ALB. "ip" target-type routes directly to pod IPs (no NodePort).

resource "kubernetes_ingress_v1" "app" {
  depends_on = [helm_release.alb_controller]

  metadata {
    name      = "app-ingress"
    namespace = var.app_namespace
    annotations = {
      "kubernetes.io/ingress.class"           = "alb"
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
    }
  }

  spec {
    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = var.app_service_name
              port {
                number = var.app_service_port
              }
            }
          }
        }
      }
    }
  }
}
