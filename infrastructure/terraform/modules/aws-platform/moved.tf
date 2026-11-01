# kubernetes provider 3.x deprecates the unversioned resources. Namespaces
# support `moved` into the _v1 type (provider >= 3.3, Terraform >= 1.8), so an
# existing state keeps them instead of replacing them. kubernetes_secret,
# kubernetes_service_account and kubernetes_storage_class have no state-move
# support; they were renamed without moved blocks (clusters are built fresh
# each session, so there is no state to carry; the dev state held no
# resources when this was written, 2026-11-01).
#
# Delete this file once every state written before the rename is gone (after
# the next full rebuild); the blocks only matter for older state.

moved {
  from = kubernetes_namespace.karpenter
  to   = kubernetes_namespace_v1.karpenter
}

moved {
  from = kubernetes_namespace.kyverno
  to   = kubernetes_namespace_v1.kyverno
}

moved {
  from = kubernetes_namespace.monitoring
  to   = kubernetes_namespace_v1.monitoring
}

moved {
  from = kubernetes_namespace.mlops
  to   = kubernetes_namespace_v1.mlops
}

moved {
  from = kubernetes_namespace.mlflow
  to   = kubernetes_namespace_v1.mlflow
}

moved {
  from = kubernetes_namespace.argo
  to   = kubernetes_namespace_v1.argo
}

moved {
  from = kubernetes_namespace.kserve
  to   = kubernetes_namespace_v1.kserve
}
