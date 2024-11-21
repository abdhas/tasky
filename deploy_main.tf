provider "aws" {
  region = "eu-north-1"
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks_cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks_cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks_auth.token
}

data "aws_eks_cluster" "eks_cluster" {
  name = "abdieks-demo"
}

data "aws_eks_cluster_auth" "eks_auth" {
  name = data.aws_eks_cluster.eks_cluster.name
}

# Define the Docker tag dynamically as a local variable
locals {
  docker_tag = formatdate("YYYYMMDDHHmmss", timestamp()) # Use valid timestamp for Docker tag
}

# Clone Tasky repository, build, tag, and push Docker image
resource "null_resource" "clone_and_build_tasky" {
  triggers = {
    force_run = local.docker_tag # Forces execution on every apply
  }

  provisioner "local-exec" {
    command = <<EOT
      set -e
      TAG=${local.docker_tag}
      if [ ! -d "./tasky" ]; then
        git clone https://github.com/abdhas/tasky.git
      fi
      cd tasky
      docker build --platform linux/amd64 -t ahassanop5/tasky:$TAG .
      docker push ahassanop5/tasky:$TAG
      cd ..
      rm -rf ./tasky # Cleanup the tasky directory
    EOT
  }
}

# ServiceAccount for the Tasky application
resource "kubernetes_service_account" "tasky_sa" {
  metadata {
    name      = "tasky-sa"
    namespace = "default"
  }

  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

# ClusterRoleBinding for cluster-wide access
resource "kubernetes_cluster_role_binding" "tasky_admin_binding" {
  metadata {
    name = "tasky-admin-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.tasky_sa.metadata[0].name
    namespace = kubernetes_service_account.tasky_sa.metadata[0].namespace
  }

  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}

# Deployment for the Tasky application
resource "kubernetes_deployment" "tasky" {
  metadata {
    name      = "tasky-deployment"
    namespace = "default"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "tasky"
      }
    }

    template {
      metadata {
        labels = {
          app = "tasky"
        }

        annotations = {
          "force-redeploy" = local.docker_tag # Dynamic annotation forces redeployment
        }
      }

      spec {
        service_account_name = kubernetes_service_account.tasky_sa.metadata[0].name

        container {
          name              = "tasky-container"
          image             = "ahassanop5/tasky:${local.docker_tag}" # Use the dynamic tag
          image_pull_policy = "Always"                               # Ensure Kubernetes pulls the image with the new tag

          port {
            container_port = 8080
          }

          env {
            name  = "MONGODB_URI"
            value = "mongodb://${ADMIN_USERNAME}:${ADMIN_PASSWORD}@10.0.0.51:27017"
          }

          env {
            name  = "SECRET_KEY"
            value = "secret123"
          }

          args = [
            "/bin/sh", "-c",
            "apt update && apt install -y curl && curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl && mv kubectl /usr/local/bin/ && sleep 3600"
          ]
        }
      }
    }
  }
}

# Service for the Tasky application
resource "kubernetes_service" "tasky" {
  metadata {
    name      = "tasky-service"
    namespace = "default"
  }

  spec {
    selector = {
      app = "tasky"
    }

    port {
      port        = 8080
      target_port = 8080
    }

    type = "LoadBalancer"
  }

  lifecycle {
    ignore_changes = [
      metadata
    ]
  }
}
