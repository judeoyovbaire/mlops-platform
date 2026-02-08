# Storage Configuration - Production
# GKE provides standard-rwo and premium-rwo StorageClasses by default.
# For RWX: Filestore CSI (min 1TiB) or Cloud Storage FUSE for ML model storage.

# Production storage considerations:
# - Use premium-rwo for databases and high-IOPS workloads
# - Use standard-rwo for general workloads
# - Consider Filestore for shared model storage across inference pods
