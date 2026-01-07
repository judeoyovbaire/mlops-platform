# =============================================================================
# Storage Configuration
# =============================================================================
# GKE automatically provides standard-rwo and premium-rwo StorageClasses
# We only define additional classes if needed

# Standard RWX StorageClass (for shared volumes)
# Uses Filestore CSI driver - only create if needed
# Note: Filestore has minimum 1TiB size requirement
# resource "kubernetes_storage_class" "standard_rwx" {
#   metadata {
#     name = "standard-rwx"
#   }
#
#   storage_provisioner = "filestore.csi.storage.gke.io"
#   reclaim_policy      = "Delete"
#   volume_binding_mode = "WaitForFirstConsumer"
#
#   parameters = {
#     tier = "standard"
#   }
#
#   allow_volume_expansion = true
#
#   depends_on = [module.gke]
# }
