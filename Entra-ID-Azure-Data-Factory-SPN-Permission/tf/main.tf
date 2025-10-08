terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

provider "azuread" {
  # The Azure AD provider uses the Azure CLI credentials by default.
  # Ensure you are logged in with 'az login'.
}

# --- 1. Configuration Variables ---
variable "resource_group_name" {
  description = "The name of the resource group for the Data Factory."
  type        = string
  default     = "adf-rg-tf"
}

variable "location" {
  description = "The Azure region where resources will be created."
  type        = string
  default     = "EastUS"
}

variable "data_factory_name" {
  description = "The globally unique name for the Azure Data Factory."
  type        = string
  default     = "my-unique-adf-tf"
}

# --- 2. Create Azure Resources ---

# Create the resource group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# Create the Azure Data Factory with a System-Assigned Managed Identity
resource "azurerm_data_factory" "adf" {
  name                = var.data_factory_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  identity {
    type = "SystemAssigned"
  }

}

# --- 3. Grant Microsoft Graph Permissions ---

# Data source to get the Service Principal for Microsoft Graph
data "azuread_service_principal" "graph" {
  client_id = "00000003-0000-0000-c000-000000000000"
}

# Assign the 'Sites.Selected' application permission to the Data Factory's managed identity
resource "azuread_app_role_assignment" "adf_graph_permission" {
  # The Service Principal of the identity being granted the permission
  principal_object_id = azurerm_data_factory.adf.identity[0].principal_id

  # The Service Principal of the API being accessed (Microsoft Graph)
  resource_object_id = data.azuread_service_principal.graph.object_id

  # The specific ID of the permission (App Role) to grant.
  # We look up the ID for the 'Sites.Selected' role from the Graph SP's available app_roles.
  app_role_id = one([
    for role in data.azuread_service_principal.graph.app_roles : role.id
    if role.value == "Sites.Selected" && contains(role.allowed_member_types, "Application")
  ])
}

# --- 4. Outputs ---
output "data_factory_portal_url" {
  description = "The URL to the Azure Data Factory in the Azure Portal."
  value       = "https://adf.azure.com/en/home?factory=${urlencode(azurerm_data_factory.adf.id)}"
}

output "managed_identity_principal_id" {
  description = "The Principal ID (Object ID) of the Data Factory's system-assigned managed identity."
  value       = azurerm_data_factory.adf.identity[0].principal_id
}