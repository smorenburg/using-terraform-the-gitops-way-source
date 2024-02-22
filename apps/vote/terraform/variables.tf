variable "app" {
  description = "Optional. The name of the application."
  type        = string
  default     = "vote"
}

variable "location" {
  description = "Optional. The location (region) for the resources."
  type        = string
  default     = "northeurope"
}

variable "location_abbreviation" {
  description = "Optional. The abbreviation of the location."
  type        = map(string)
  default = {
    "westeurope"  = "weu"
    "northeurope" = "neu"
    "eastus"      = "eus"
    "westus"      = "wus"
    "ukwest"      = "ukw"
    "uksouth"     = "uks"
  }
}

variable "container_image" {
  description = "Required. The image for the container."
  type        = string
}

variable "ingress_rule_host" {
  description = "Required. The host for the ingress rule."
  type        = string
}
