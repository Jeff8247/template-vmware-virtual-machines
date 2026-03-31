terraform {
  required_version = ">= 1.3, < 2.0"

  # --- Remote Backend (Recommended for Production) ---
  # To enable S3 backend, uncomment the block below and run 'terraform init'
  # backend "s3" {
  #   bucket         = "my-terraform-state-bucket"
  #   key            = "deployments/template-vmware-virtual-machines/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-lock-table"  # Optional: for state locking
  # }

  required_providers {
    vsphere = {
      source  = "vmware/vsphere"
      version = "~> 2.6"
    }
  }
}
