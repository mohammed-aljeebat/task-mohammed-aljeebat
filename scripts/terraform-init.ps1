$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path "$PSScriptRoot\..\terraform")
terraform init
terraform validate
terraform plan -var-file=terraform.tfvars.example -out=quest.tfplan
