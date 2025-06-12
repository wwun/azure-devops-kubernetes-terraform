# Terraform script to create an EKS cluster on AWS
# This script uses the Terraform AWS and Kubernetes providers to create an EKS cluster
# and a default node group. It also sets up the necessary IAM roles and permissions.

# aws --version
# aws eks --region us-east-1 update-kubeconfig --name in28minutes-cluster
# Uses default VPC and Subnet. Create Your Own VPC and Private Subnets for Prod Usage.
# terraform-backend-state-in28minutes-123
# AKIA4AHVNOD7OOO6T4KI


terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
  }

  backend "s3" {
    bucket = "mybucket" # Will be overridden from build
    key    = "path/to/my/key" # Will be overridden from build
    region = "us-east-1"
  }
}

# Needed to set the default region
provider "aws" {
  region = "us-east-1"
}

resource "aws_default_vpc" "default" {

}

data "aws_subnet_ids" "subnets" {
  vpc_id = aws_default_vpc.default.id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

module "in28minutes-cluster" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 19.0"

  cluster_name    = "in28minutes-cluster"
  cluster_version = "1.24"
  vpc_id          = aws_default_vpc.default.id
  subnet_ids      = data.aws_subnet_ids.subnets.ids

  # Default node group settings (optional, applies to all node groups if used)
  eks_managed_node_group_defaults = {
    ami_type       = "AL2_x86_64"
    instance_types = ["t2.micro"]
  }

  enable_irsa = true
}

resource "aws_eks_node_group" "default" {
  cluster_name    = module.in28minutes-cluster.cluster_name
  node_group_name = "default"
  node_role_arn   = module.in28minutes-cluster.eks_managed_node_group_iam_role_arn
  subnet_ids      = module.in28minutes-cluster.subnet_ids

  scaling_config {
    desired_size = 3
    max_size     = 5
    min_size     = 3
  }

  instance_types = ["t2.micro"]

  depends_on = [module.in28minutes-cluster]
}

data "aws_eks_cluster" "cluster" {
  name = module.in28minutes-cluster.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.in28minutes-cluster.cluster_id
}


# We will use ServiceAccount to connect to K8S Cluster in CI/CD mode
# ServiceAccount needs permissions to create deployments 
# and services in default namespace
resource "kubernetes_cluster_role_binding" "example" {
  metadata {
    name = "fabric8-rbac"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = "default"
  }
}