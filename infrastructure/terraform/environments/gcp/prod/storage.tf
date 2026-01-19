# =============================================================================
# Storage Configuration - Production
# =============================================================================
# GKE automatically provides standard-rwo and premium-rwo StorageClasses
#
# For production workloads requiring shared volumes (RWX), consider:
# - Filestore CSI driver (minimum 1TiB, suitable for production)
# - Cloud Storage FUSE for read-heavy ML model storage
#
# See: https://cloud.google.com/filestore/docs/creating-instances

# Production storage considerations:
# - Use premium-rwo for databases and high-IOPS workloads
# - Use standard-rwo for general workloads
# - Consider Filestore for shared model storage across inference pods
