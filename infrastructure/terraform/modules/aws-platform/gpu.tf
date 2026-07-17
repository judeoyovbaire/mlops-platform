# GPU node enablement (JDH-376).
#
# Karpenter's al2023@latest alias resolves to the NVIDIA AMI variant for GPU
# instance types (drivers + container toolkit), but the DEVICE PLUGIN that
# exposes nvidia.com/gpu to the scheduler is NOT part of the AMI - without
# this daemonset, GPU nodes boot with working drivers and zero schedulable
# GPUs. Scoped to the GPU pool via nodeSelector + toleration so it never
# runs on CPU nodes.
resource "helm_release" "nvidia_device_plugin" {
  name       = "nvidia-device-plugin"
  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  version    = var.helm_nvidia_device_plugin_version
  namespace  = "kube-system"

  values = [yamlencode({
    nodeSelector = { "node-type" = "gpu" }
    # The chart defaults to a nodeAffinity requiring node-feature-discovery
    # / gpu-operator labels (pci-10de.present, nvidia.com/gpu.present) that
    # this platform does not run - it AND-combines with our nodeSelector,
    # so desired=0 and no GPU is ever advertised. Override to empty: the
    # nodeSelector + toleration below fully scope the daemonset to the
    # Karpenter GPU pool.
    affinity     = {}
    tolerations = [{
      key      = "nvidia.com/gpu"
      operator = "Equal"
      value    = "true"
      effect   = "NoSchedule"
    }]
  })]

  depends_on = [helm_release.karpenter]
}
