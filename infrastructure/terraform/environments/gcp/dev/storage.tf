# =============================================================================
# Storage Configuration
# =============================================================================
# Configures Kubernetes StorageClasses for GKE

# Standard RWO StorageClass (default)
# Uses GCE Persistent Disk with SSD
resource "kubernetes_storage_class" "standard_rwo" {
  metadata {
    name = "standard-rwo"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "pd.csi.storage.gke.io"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    type = "pd-balanced"
  }

  allow_volume_expansion = true

  depends_on = [module.gke]
}

# Premium SSD StorageClass (for high-performance workloads)
resource "kubernetes_storage_class" "premium_rwo" {
  metadata {
    name = "premium-rwo"
  }

  storage_provisioner = "pd.csi.storage.gke.io"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    type = "pd-ssd"
  }

  allow_volume_expansion = true

  depends_on = [module.gke]
}

# Standard RWX StorageClass (for shared volumes)
# Uses Filestore CSI driver
resource "kubernetes_storage_class" "standard_rwx" {
  metadata {
    name = "standard-rwx"
  }

  storage_provisioner = "filestore.csi.storage.gke.io"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    tier = "standard"
  }

  allow_volume_expansion = true

  depends_on = [module.gke]
}
