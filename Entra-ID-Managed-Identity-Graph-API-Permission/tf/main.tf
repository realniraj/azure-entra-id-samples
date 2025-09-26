# This configuration requires both the AzureRM and AzureAD providers.
# The AzureAD provider is used to manage Entra ID resources like service principals and permissions.
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {}
}

# Configure the Azure Active Directory Provider
provider "azuread" {}

# --- 1. Define Variables ---
variable "resource_group_name" {
  description = "The name of the resource group."
  type        = string
  default     = "my-managed-identity-rg-tf"
}

variable "location" {
  description = "The Azure region where resources will be created."
  type        = string
  default     = "eastus"
}

variable "managed_identity_name" {
  description = "The name of the user-assigned managed identity."
  type        = string
  default     = "mySampleWebAppIdentity-tf"
}

variable "graph_permissions" {
  description = "A list of Microsoft Graph application permissions to assign to the managed identity."
  type        = list(string)
  default     = ["User.Read.All", "Group.Read.All"]
}

# --- 2. Create Azure Resources ---
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_user_assigned_identity" "identity" {
  name                = var.managed_identity_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

# --- 3. Find Microsoft Graph and Assign Permissions ---

# Data source to get the Microsoft Graph service principal using its well-known App ID
data "azuread_service_principal" "graph" {
  client_id = "00000003-0000-0000-c000-000000000000"
}

resource "azuread_app_role_assignment" "graph_permissions" {
  for_each = toset(var.graph_permissions)

  app_role_id          = data.azuread_service_principal.graph.app_role_ids[each.key]
  principal_object_id = azurerm_user_assigned_identity.identity.principal_id
  resource_object_id   = data.azuread_service_principal.graph.object_id
}