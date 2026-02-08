# Azure Environment Outputs

# -----------------------------------------------------------------------------
# Cluster Information
# -----------------------------------------------------------------------------

output "cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.aks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for the AKS cluster API server"
  value       = module.aks.cluster_endpoint
  sensitive   = true
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = module.aks.configure_kubectl
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = module.aks.resource_group_name
}

# -----------------------------------------------------------------------------
# Storage Information
# -----------------------------------------------------------------------------

output "storage_account_name" {
  description = "Name of the MLflow storage account"
  value       = module.aks.storage_account_name
}

output "acr_login_server" {
  description = "Login server for the Azure Container Registry"
  value       = module.aks.acr_login_server
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = module.aks.key_vault_name
}

# -----------------------------------------------------------------------------
# Database Information
# -----------------------------------------------------------------------------

output "postgresql_fqdn" {
  description = "FQDN of the PostgreSQL server"
  value       = module.aks.postgresql_fqdn
}

# -----------------------------------------------------------------------------
# Access Information
# -----------------------------------------------------------------------------

output "access_info" {
  description = "Access information for deployed services"
  value       = <<-EOT

    ============================================
    MLOps Platform - Azure AKS Deployment
    ============================================

    1. Configure kubectl:
       ${module.aks.configure_kubectl}

    2. Access MLflow:
       kubectl port-forward svc/mlflow 5000:5000 -n mlflow
       Open: http://localhost:5000

    3. Access ArgoCD:
       kubectl port-forward svc/argocd-server 8080:443 -n argocd
       Open: https://localhost:8080
       Username: admin
       Password: az keyvault secret show --vault-name ${module.aks.key_vault_name} --name argocd-admin-password --query value -o tsv

    4. Access Grafana:
       kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring
       Open: http://localhost:3000
       Username: admin
       Password: az keyvault secret show --vault-name ${module.aks.key_vault_name} --name grafana-admin-password --query value -o tsv

    5. Access Argo Workflows:
       kubectl port-forward svc/argo-workflows-server 2746:2746 -n argo
       Open: http://localhost:2746

    6. Push images to ACR:
       az acr login --name ${module.aks.acr_login_server}
       docker tag myimage:latest ${module.aks.acr_login_server}/myimage:latest
       docker push ${module.aks.acr_login_server}/myimage:latest

  EOT
}
