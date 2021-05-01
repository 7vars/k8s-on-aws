resource "aws_security_group" "eks-master" {
    name        = "eks-cluster-${var.cluster_name}"
    description = "Cluster communication with worker nodes"
    vpc_id      = aws_vpc.vpc.id
 
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
    
    tags = {
        "Name" = "eks-cluster-${var.cluster_name}"
        "Environment" = var.cluster_name
    }
}

resource "aws_security_group" "eks-node" {
    name        = "eks-node-${var.cluster_name}"
    description = "Security group for all nodes in the cluster"
    vpc_id      = aws_vpc.vpc.id
 
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
 
    tags = {
        "Name" = "eks-node-${var.cluster_name}"
        "Environment" = var.cluster_name
    }
}


resource "aws_security_group_rule" "eks-master-ingress-workstation-https" {
  cidr_blocks       = var.whitelisted_hosts
  description       = "Allow workstation to communicate with the cluster API Server."
  from_port         = 443
  protocol          = "tcp"
  security_group_id = aws_security_group.eks-master.id
  to_port           = 443
  type              = "ingress"
}


resource "aws_security_group_rule" "eks-node-ingress-self" {
  description              = "Allow nodes to communicate with each other"
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.eks-node.id
  source_security_group_id = aws_security_group.eks-node.id
  to_port                  = 65535
  type                     = "ingress"
}
 
resource "aws_security_group_rule" "eks-node-ingress-cluster" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  from_port                = 1025
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks-node.id
  source_security_group_id = aws_security_group.eks-master.id
  to_port                  = 65535
  type                     = "ingress"
}
 
resource "aws_security_group_rule" "eks-cluster-ingress-node-https" {
  description              = "Allow pods to communicate with the cluster API Server"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks-node.id
  source_security_group_id = aws_security_group.eks-master.id
  to_port                  = 443
  type                     = "ingress"
}
 
resource "aws_security_group_rule" "eks-node-ingress-master" {
  description              = "Allow cluster control to receive communication from the worker Kubelets"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks-master.id
  source_security_group_id = aws_security_group.eks-node.id
  to_port                  = 443
  type                     = "ingress"
}


# master
resource "aws_iam_role" "eks-master" {
  name = "terraform-eks-cluster"
 
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}
 
resource "aws_iam_role_policy_attachment" "cluster-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role = aws_iam_role.eks-master.name
}
 
resource "aws_iam_role_policy_attachment" "cluster-AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role = aws_iam_role.eks-master.name
}


resource "aws_eks_cluster" "eks-master" {
  name            = var.cluster_name
  role_arn        = aws_iam_role.eks-master.arn
  version = var.k8s_version
 
  vpc_config {
    security_group_ids = [aws_security_group.eks-master.id]
    subnet_ids         = aws_subnet.cluster_subnet.*.id
  }
 
  depends_on = [
    aws_iam_role_policy_attachment.cluster-AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster-AmazonEKSServicePolicy,
  ]
}


# worker
resource "aws_iam_role" "eks-node" {
  name = "terraform-eks-tf-eks-node"
 
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}
 
resource "aws_iam_role_policy_attachment" "eks-node-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks-node.name
}
 
resource "aws_iam_role_policy_attachment" "eks-node-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks-node.name
}
 
resource "aws_iam_role_policy_attachment" "eks-node-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks-node.name
}
 
resource "aws_iam_instance_profile" "node" {
  name = "eks-node"
  role = aws_iam_role.eks-node.name
}


locals {
    eks-node-userdata = <<USERDATA
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.eks-master.endpoint}' --b64-cluster-ca '${aws_eks_cluster.eks-master.certificate_authority.0.data}' '${var.cluster_name}'
USERDATA
}

resource "aws_key_pair" "cluster_key" {
    key_name = "clusterPublicKey"
    public_key = file(var.public_key_path)
}

data "aws_ami" "eks_worker_base" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.k8s_version}*"]
  }
  most_recent = true
  # Owner ID of AWS EKS team
  owners = ["602401143452"]
}

resource "aws_launch_configuration" "node" {
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.node.name
  image_id                    = data.aws_ami.eks_worker_base.id
  instance_type               = var.node_instance_type
  name_prefix                 = "eks"
  security_groups             = [aws_security_group.eks-node.id]
  user_data_base64            = base64encode(local.eks-node-userdata)
  key_name                    = aws_key_pair.cluster_key.key_name
 
  lifecycle {
    create_before_destroy = true
  }

  root_block_device {
      encrypted = true
  }
}

resource "aws_autoscaling_group" "node" {
  desired_capacity     = var.node_count
  launch_configuration = aws_launch_configuration.node.id
  max_size             = var.max_node_count
  min_size             = "1"
  name                 = var.autoscaling_group_name

  vpc_zone_identifier  = aws_subnet.cluster_subnet.*.id
  target_group_arns = [ aws_lb_target_group.eks.arn ]
 
  tag {
    key                 = "Name"
    value               = var.autoscaling_group_name
    propagate_at_launch = true
  }
 
  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }
}

