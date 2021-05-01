resource "null_resource" "deploy_traefik" {
  provisioner "local-exec" {
    #command = "env PUBLIC_DOMAIN=${var.public_domain} envsubst < ./traefik/deployment.yaml | kubectl apply -f -"
    command = "env PUBLIC_DOMAIN=${aws_alb.eks-alb.dns_name} envsubst < ./traefik/deployment.yaml | kubectl apply -f -"
  }

  depends_on = [
    null_resource.update_kubeconfig,
  ]
}
