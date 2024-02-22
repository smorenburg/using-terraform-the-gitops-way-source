terraform {
  required_providers {
    azurerm = {
      version = ">= 3.84"
    }

    random = {
      version = ">= 3.6"
    }

    kubernetes = {
      version = ">= 2.24"
    }

    # TODO: Start using version 0.8 by adding the atlas-cli to the tf-runner container image.
    atlas = {
      source  = "ariga/atlas"
      version = "0.7"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "atlas" {}

data "azurerm_client_config" "current" {}

# Configure the Terraform remote state backend.
data "terraform_remote_state" "environment" {
  backend = "azurerm"

  config = {
    storage_account_name = var.storage_account
    resource_group_name  = var.resource_group
    container_name       = "tfstate"
    key                  = "${var.environment}.${var.location}.tfstate"
  }
}

# TODO: Add comments.
data "atlas_schema" "default" {
  src     = file("templates/schema.hcl")
  dev_url = join("", [
    "mysql://root@",
    kubernetes_service_v1.mysql_schema.metadata[0].name,
    ".",
    kubernetes_namespace_v1.default.metadata[0].name,
    ".svc.cluster.local"
  ])

  depends_on = [kubernetes_deployment_v1.mysql_schema]
}

locals {
  # Lookup and set the location abbreviation, defaults to na (not available).
  location_abbreviation = try(var.location_abbreviation[var.location], "na")

  # Lookup and set the environment abbreviation, defaults to na (not available).
  environment_abbreviation = try(var.environment_abbreviation[var.environment], "na")

  # Construct the name suffix.
  suffix = "${var.app}-${local.environment_abbreviation}-${local.location_abbreviation}"

  # Construct the data source name,
  dsn = join("", [
    random_pet.mysql_login.id,
    ":",
    random_password.mysql_password.result,
    "@",
    "tcp(${azurerm_mysql_flexible_server.default.fqdn})",
    "/snippetbox",
    "?parseTime=true&tls=preferred&multiStatements=true",
  ])
}

resource "random_pet" "mysql_login" {
  length = 1
}

resource "random_password" "mysql_password" {
  length = 16
}

# Generate a random suffix for the Azure Database for MySQL flexible server.
resource "random_string" "mysql" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_key_vault_secret" "mysql_login" {
  name         = "${var.app}-mysql-login"
  value        = random_pet.mysql_login.id
  key_vault_id = data.terraform_remote_state.environment.outputs.azurerm_key_vault_default_id
}

resource "azurerm_key_vault_secret" "mysql_password" {
  name         = "${var.app}-mysql-password"
  value        = random_password.mysql_password.result
  key_vault_id = data.terraform_remote_state.environment.outputs.azurerm_key_vault_default_id
}

# Create the resource group.
resource "azurerm_resource_group" "default" {
  name     = "rg-${local.suffix}"
  location = var.location

  tags = {
    part-of = var.app
  }
}

resource "azurerm_mysql_flexible_server" "default" {
  name                   = "mysql-${var.app}-${local.environment_abbreviation}-${random_string.mysql.result}"
  resource_group_name    = azurerm_resource_group.default.name
  location               = var.location
  administrator_login    = random_pet.mysql_login.id
  administrator_password = random_password.mysql_password.result
  sku_name               = "B_Standard_B1s" # TODO: Add sku_name as a variable.
  zone                   = "1" # TODO: Add high-availability.

  tags = {
    component = "database"
    part-of   = var.app
  }
}

resource "azurerm_mysql_flexible_server_firewall_rule" "allow_all" {
  name                = "AllowAll"
  resource_group_name = azurerm_resource_group.default.name
  server_name         = azurerm_mysql_flexible_server.default.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "255.255.255.255"
}

resource "atlas_schema" "default" {
  hcl     = data.atlas_schema.default.hcl
  dev_url = data.atlas_schema.default.dev_url
  url     = join("", [
    "mysql://",
    random_pet.mysql_login.id,
    ":",
    urlencode(random_password.mysql_password.result),
    "@",
    azurerm_mysql_flexible_server.default.fqdn,
    "?tls=preferred"
  ])

  depends_on = [azurerm_mysql_flexible_server_firewall_rule.allow_all]
}

# Create the Kubernetes namespace.
resource "kubernetes_namespace_v1" "default" {
  metadata {
    name = var.app

    labels = {
      name    = var.app
      part-of = var.app
    }
  }
}

# Create the mysql-schema Kubernetes deployment.
resource "kubernetes_deployment_v1" "mysql_schema" {
  metadata {
    name      = "mysql-schema"
    namespace = kubernetes_namespace_v1.default.metadata[0].name

    labels = {
      name      = "mysql-schema"
      component = "database"
      part-of   = var.app
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        name      = "mysql-schema"
        component = "database"
        part-of   = var.app
      }
    }

    template {
      metadata {
        labels = {
          name      = "mysql-schema"
          component = "database"
          part-of   = var.app
        }
      }

      spec {
        container {
          image = "mysql:8"
          name  = "mysql-schema"

          port {
            container_port = 3306
            protocol       = "TCP"
          }

          env {
            name  = "MYSQL_ALLOW_EMPTY_PASSWORD"
            value = true
          }

          resources {
            limits = {
              cpu    = "0.5"
              memory = "1Gi"
            }
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
          }

          liveness_probe {
            tcp_socket {
              port = "3306"
            }

            initial_delay_seconds = 15
          }
        }
      }
    }
  }
}

# Create the mysql-schema Kubernetes service.
resource "kubernetes_service_v1" "mysql_schema" {
  metadata {
    name      = "mysql-schema"
    namespace = kubernetes_namespace_v1.default.metadata[0].name

    labels = {
      name      = "mysql-schema"
      component = "database"
      part-of   = var.app
    }
  }

  spec {
    selector = {
      name      = "mysql-schema"
      component = "database"
      part-of   = var.app
    }

    port {
      port        = 3306
      target_port = 3306
    }
  }
}

# Create the snipperbox Kubernetes deployment.
resource "kubernetes_deployment_v1" "snipperbox" {
  metadata {
    name      = var.app
    namespace = kubernetes_namespace_v1.default.metadata[0].name

    labels = {
      name      = var.app
      component = "server"
      part-of   = var.app
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        name      = var.app
        component = "server"
        part-of   = var.app
      }
    }

    template {
      metadata {
        labels = {
          name      = var.app
          component = "server"
          part-of   = var.app
        }
      }

      spec {
        container {
          image = var.container_image
          name  = var.app

          port {
            container_port = 4000
            protocol       = "TCP"
          }

          # TODO: Store the arg in a secret (file). Develop the feature in Snippetbox first.
          args = ["-dsn", local.dsn]

          resources {
            limits = {
              cpu    = "0.5"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "50Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 4000
            }

            initial_delay_seconds = 10
          }
        }
      }
    }
  }
}

# Create the snipperbox Kubernetes service.
resource "kubernetes_service_v1" "snipperbox" {
  metadata {
    name      = var.app
    namespace = kubernetes_namespace_v1.default.metadata[0].name

    labels = {
      name      = var.app
      component = "server"
      part-of   = var.app
    }
  }

  spec {
    selector = {
      name      = var.app
      component = "server"
      part-of   = var.app
    }

    port {
      port        = 80
      target_port = 4000
    }
  }
}

# Create the ingress.
resource "kubernetes_ingress_v1" "default" {
  metadata {
    name      = var.app
    namespace = kubernetes_namespace_v1.default.metadata[0].name

    labels = {
      name    = var.app
      part-of = var.app
    }

    annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt"
    }
  }

  spec {
    tls {
      hosts       = [var.ingress_rule_host]
      secret_name = var.app
    }

    rule {
      host = var.ingress_rule_host

      http {
        path {
          backend {
            service {
              name = var.app
              port {
                number = 80
              }
            }
          }

          path      = "/"
          path_type = "Prefix"
        }
      }
    }
  }
}
