resource "null_resource" "deploy_keycloak" {
  provisioner "local-exec" {
    #command = "env PUBLIC_DOMAIN=${var.public_domain} envsubst < ./keycloak/deployment.yaml | kubectl apply -f -"
    command = "env PUBLIC_DOMAIN=${aws_alb.eks-alb.dns_name} envsubst < ./keycloak/deployment.yaml | kubectl apply -f -"
  }

  depends_on = [
    null_resource.update_kubeconfig,
    null_resource.deploy_traefik,
  ]
}