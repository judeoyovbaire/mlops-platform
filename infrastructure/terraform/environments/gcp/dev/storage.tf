# Storage Configuration
# GKE automatically provides standard-rwo and premium-rwo StorageClasses
#
# For shared volumes (RWX), enable Filestore CSI driver and create a StorageClass.
# Note: Filestore has minimum 1TiB size requirement, making it unsuitable for dev.
# See: https://cloud.google.com/filestore/docs/creating-instances