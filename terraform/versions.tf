terraform {
    required_version = ">= 1.7.0"

    # Remote state so Terraform runs consistently from GitHub Actions runners
    # (which have no local state between runs). This reuses the Storage Account
    # already created by this same Terraform config.
    #
    # One-time setup before first CI run:
    #   az storage container create --name tfstate --account-name mihirstorage225113768
    #   cd terraform
    #   terraform init -migrate-state

    required_providers {
        azurerm = {
            source  = "hashicorp/azurerm"
            version = "~> 4.0"
        }

        local = {
            source  = "hashicorp/local"
            version = "~> 2.5"
        }
    }
}

provider "azurerm" {
    features {}
}