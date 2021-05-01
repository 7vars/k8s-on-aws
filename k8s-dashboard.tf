resource "null_resource" "deploy_k8s_dashboard" {
  provisioner "local-exec" {
      command = "kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0/aio/deploy/recommended.yaml"
  }

  depends_on = [
    null_resource.update_kubeconfig,
    null_resource.deploy_traefik,
  ]
}

resource "null_resource" "deploy_k8s_dashboard_ingress" {
  provisioner "local-exec" {
    #command = "env PUBLIC_DOMAIN=${var.public_domain} envsubst < ./dashboard/deployment.yaml | kubectl apply -f -"
    command = "env PUBLIC_DOMAIN=${aws_alb.eks-alb.dns_name} envsubst < ./dashboard/deployment.yaml | kubectl apply -f -"
  }

  depends_on = [
    null_resource.deploy_k8s_dashboard,
  ]
}
