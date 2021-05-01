provider "kubernetes" {
  host                      = aws_eks_cluster.eks-master.endpoint
  cluster_ca_certificate    = base64decode(aws_eks_cluster.eks-master.certificate_authority.0.data)
  token                     = data.external.aws_iam_authenticator.result.token
  load_config_file          = false
}

data "external" "aws_iam_authenticator" {
  program = ["sh", "-c", "aws-iam-authenticator token -i ${var.cluster_name} | jq -r -c .status"]
}

resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name = "aws-auth"
    namespace = "kube-system"
  }
  data = {
    mapRoles = <<EOF
- rolearn: ${aws_iam_role.eks-node.arn}
  username: system:node:{{EC2PrivateDNSName}}
  groups:
    - system:bootstrappers
    - system:nodes
EOF
  }
  depends_on = [
    aws_eks_cluster.eks-master
  ]
}

resource "null_resource" "update_kubeconfig" {
  provisioner "local-exec" {
    command = "aws eks --region ${var.region} update-kubeconfig --name ${var.cluster_name}"
  }

  depends_on = [
    kubernetes_config_map.aws_auth
  ]
}