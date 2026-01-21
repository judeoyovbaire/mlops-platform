# =============================================================================
# Karpenter - GPU Autoscaling
# =============================================================================

# Karpenter namespace
resource "kubernetes_namespace" "karpenter" {
  metadata {
    name = "karpenter"
    labels = {
      "app.kubernetes.io/name"    = "karpenter"
      "app.kubernetes.io/part-of" = "mlops-platform"
      # Karpenter needs baseline for node management
      "pod-security.kubernetes.io/enforce"         = "baseline"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/warn"            = "baseline"
      "pod-security.kubernetes.io/warn-version"    = "latest"
      "pod-security.kubernetes.io/audit"           = "baseline"
      "pod-security.kubernetes.io/audit-version"   = "latest"
    }
  }

  depends_on = [module.eks]
}

# Cleanup Karpenter-managed nodes before destroying Karpenter
# This prevents orphaned EC2 instances when running terraform destroy
resource "null_resource" "karpenter_cleanup" {
  triggers = {
    cluster_name = module.eks.cluster_name
    region       = var.aws_region
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Cleaning up Karpenter-managed nodes..."

      # Update kubeconfig
      aws eks update-kubeconfig --region ${self.triggers.region} --name ${self.triggers.cluster_name} 2>/dev/null || true

      # Delete all NodePools to trigger node cleanup
      kubectl delete nodepools --all --ignore-not-found=true 2>/dev/null || true

      # Delete all EC2NodeClasses
      kubectl delete ec2nodeclasses --all --ignore-not-found=true 2>/dev/null || true

      # Wait for Karpenter to terminate nodes (max 5 minutes)
      echo "Waiting for Karpenter nodes to terminate..."
      for i in $(seq 1 30); do
        NODE_COUNT=$(kubectl get nodes -l karpenter.sh/registered=true --no-headers 2>/dev/null | wc -l || echo "0")
        if [ "$NODE_COUNT" -eq 0 ]; then
          echo "All Karpenter nodes terminated"
          break
        fi
        echo "Waiting for $NODE_COUNT Karpenter nodes to terminate... ($i/30)"
        sleep 10
      done

      echo "Karpenter cleanup complete"
    EOT
  }

  depends_on = [module.eks]
}

# Karpenter Helm release
resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.helm_karpenter_version
  namespace  = kubernetes_namespace.karpenter.metadata[0].name

  # Increase timeout for CRD installation
  timeout = 600

  set {
    name  = "settings.clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "settings.clusterEndpoint"
    value = module.eks.cluster_endpoint
  }

  # Fix feature gates - all must be explicitly set for Karpenter 1.8+
  # Empty values cause panic: strconv.ParseBool parsing ""
  set {
    name  = "settings.featureGates.spotToSpotConsolidation"
    value = "false"
  }

  set {
    name  = "settings.featureGates.nodeRepair"
    value = "false"
  }

  set {
    name  = "settings.featureGates.staticCapacity"
    value = "false"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.karpenter_irsa_role_arn
  }

  # Resource requests
  set {
    name  = "controller.resources.requests.cpu"
    value = "200m"
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "512Mi"
  }

  # Resource limits (sized for medium cluster)
  set {
    name  = "controller.resources.limits.cpu"
    value = "2"
  }

  set {
    name  = "controller.resources.limits.memory"
    value = "2Gi"
  }

  depends_on = [
    kubernetes_namespace.karpenter,
    time_sleep.alb_controller_ready,
    null_resource.karpenter_cleanup
  ]
}

# Karpenter NodePool for GPU workloads
resource "kubectl_manifest" "karpenter_gpu_nodepool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: gpu-workloads
    spec:
      template:
        metadata:
          labels:
            node-type: gpu
            karpenter.sh/capacity-type: spot
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: gpu
          requirements:
            - key: karpenter.k8s.aws/instance-category
              operator: In
              values: ["g", "p"]
            - key: karpenter.k8s.aws/instance-family
              operator: In
              values: ["g4dn", "g5", "p3", "p4d"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot", "on-demand"]
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
          taints:
            - key: nvidia.com/gpu
              value: "true"
              effect: NoSchedule
      limits:
        cpu: "100"
        memory: 400Gi
        nvidia.com/gpu: "8"
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 1m
      # Cost optimization: terminate GPU nodes after 4 hours to prevent runaway costs
      expireAfter: 4h
  YAML

  depends_on = [helm_release.karpenter]
}

# Karpenter NodePool for training workloads (CPU)
resource "kubectl_manifest" "karpenter_training_nodepool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: training-workloads
    spec:
      template:
        metadata:
          labels:
            node-type: training
            karpenter.sh/capacity-type: spot
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          requirements:
            - key: karpenter.k8s.aws/instance-category
              operator: In
              values: ["c", "m", "r"]
            - key: karpenter.k8s.aws/instance-size
              operator: In
              values: ["xlarge", "2xlarge", "4xlarge"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["spot"]
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
          taints:
            - key: workload
              value: training
              effect: NoSchedule
      limits:
        cpu: "200"
        memory: 800Gi
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 30s
  YAML

  depends_on = [helm_release.karpenter]
}

# Karpenter NodePool for general platform workloads (no taints)
# Used for system pods like Prometheus, ArgoCD, etc.
resource "kubectl_manifest" "karpenter_general_nodepool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: general-workloads
    spec:
      template:
        metadata:
          labels:
            node-type: general
            karpenter.sh/capacity-type: on-demand
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          requirements:
            - key: karpenter.k8s.aws/instance-category
              operator: In
              values: ["m", "c", "r"]
            - key: karpenter.k8s.aws/instance-size
              operator: In
              values: ["large", "xlarge", "2xlarge"]
            - key: karpenter.sh/capacity-type
              operator: In
              values: ["on-demand", "spot"]
            - key: kubernetes.io/arch
              operator: In
              values: ["amd64"]
          # No taints - general workloads can schedule here
      limits:
        cpu: "100"
        memory: 400Gi
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 5m
      weight: 100  # Higher weight = prefer this pool for general workloads
  YAML

  depends_on = [helm_release.karpenter]
}

# Karpenter EC2NodeClass for GPU instances
resource "kubectl_manifest" "karpenter_gpu_nodeclass" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: gpu
    spec:
      amiSelectorTerms:
        - alias: al2023@latest
      role: ${module.eks.karpenter_node_role_name}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: 100Gi
            volumeType: gp3
            deleteOnTermination: true
            encrypted: true
      tags:
        Environment: dev
        Project: mlops-platform
        NodeType: gpu
  YAML

  depends_on = [helm_release.karpenter]
}

# Karpenter EC2NodeClass for default/training instances
resource "kubectl_manifest" "karpenter_default_nodeclass" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      amiSelectorTerms:
        - alias: al2023@latest
      role: ${module.eks.karpenter_node_role_name}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: 50Gi
            volumeType: gp3
            deleteOnTermination: true
            encrypted: true
      tags:
        Environment: dev
        Project: mlops-platform
        NodeType: training
  YAML

  depends_on = [helm_release.karpenter]
}
