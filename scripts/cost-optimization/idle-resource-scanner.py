#!/usr/bin/env python3
"""
Idle Resource Scanner.

Identifies underutilized resources in the MLOps platform for cost optimization.
Scans for:
- Idle inference endpoints
- Underutilized node pools
- Orphaned storage volumes
- Unused container images
"""

import argparse
import json
import sys
from datetime import datetime, timedelta
from typing import Dict, List, Any

try:
    from kubernetes import client, config
except ImportError:
    print("kubernetes package required: pip install kubernetes")
    sys.exit(1)


class IdleResourceScanner:
    """Scans for idle and underutilized resources."""

    def __init__(self, namespace: str = None, idle_threshold_hours: int = 24):
        """
        Initialize the scanner.

        Args:
            namespace: Kubernetes namespace to scan (None for all)
            idle_threshold_hours: Hours of inactivity to consider resource idle
        """
        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        self.v1 = client.CoreV1Api()
        self.apps_v1 = client.AppsV1Api()
        self.custom_api = client.CustomObjectsApi()
        self.namespace = namespace
        self.idle_threshold = timedelta(hours=idle_threshold_hours)
        self.findings: List[Dict[str, Any]] = []

    def scan_all(self) -> Dict[str, Any]:
        """Run all scans and return findings."""
        print("Starting idle resource scan...")

        self.scan_idle_pods()
        self.scan_underutilized_deployments()
        self.scan_orphaned_pvcs()
        self.scan_idle_services()
        self.scan_inference_services()

        return self._generate_report()

    def scan_idle_pods(self) -> None:
        """Scan for pods with no recent activity."""
        print("Scanning for idle pods...")

        if self.namespace:
            pods = self.v1.list_namespaced_pod(self.namespace)
        else:
            pods = self.v1.list_pod_for_all_namespaces()

        for pod in pods.items:
            # Check if pod is in Running state but consuming minimal resources
            if pod.status.phase == "Running":
                # Check container restart count as activity indicator
                total_restarts = sum(
                    cs.restart_count for cs in (pod.status.container_statuses or [])
                )

                # Check last state change time
                conditions = pod.status.conditions or []
                last_transition = None
                for cond in conditions:
                    if cond.last_transition_time:
                        if not last_transition or cond.last_transition_time > last_transition:
                            last_transition = cond.last_transition_time

                if last_transition:
                    age = datetime.now(last_transition.tzinfo) - last_transition
                    if age > self.idle_threshold and total_restarts == 0:
                        self.findings.append({
                            "type": "idle_pod",
                            "severity": "low",
                            "resource": f"{pod.metadata.namespace}/{pod.metadata.name}",
                            "details": {
                                "age_hours": age.total_seconds() / 3600,
                                "restarts": total_restarts,
                                "phase": pod.status.phase
                            },
                            "recommendation": "Review if pod is still needed or scale down"
                        })

    def scan_underutilized_deployments(self) -> None:
        """Scan for deployments with more replicas than needed."""
        print("Scanning for underutilized deployments...")

        mlops_namespaces = ["mlops", "mlflow", "kserve", "argo"]

        for ns in mlops_namespaces:
            try:
                deployments = self.apps_v1.list_namespaced_deployment(ns)
                for dep in deployments.items:
                    spec_replicas = dep.spec.replicas or 1
                    ready_replicas = dep.status.ready_replicas or 0

                    # Flag if all replicas ready but > 2 (potential over-provisioning)
                    if spec_replicas >= 3 and ready_replicas == spec_replicas:
                        self.findings.append({
                            "type": "overprovisioned_deployment",
                            "severity": "medium",
                            "resource": f"{ns}/{dep.metadata.name}",
                            "details": {
                                "replicas": spec_replicas,
                                "ready": ready_replicas
                            },
                            "recommendation": f"Consider reducing replicas if traffic is low"
                        })
            except client.ApiException:
                continue

    def scan_orphaned_pvcs(self) -> None:
        """Scan for PVCs not attached to any pod."""
        print("Scanning for orphaned PVCs...")

        if self.namespace:
            pvcs = self.v1.list_namespaced_persistent_volume_claim(self.namespace)
            pods = self.v1.list_namespaced_pod(self.namespace)
        else:
            pvcs = self.v1.list_persistent_volume_claim_for_all_namespaces()
            pods = self.v1.list_pod_for_all_namespaces()

        # Build set of PVCs in use
        used_pvcs = set()
        for pod in pods.items:
            for volume in (pod.spec.volumes or []):
                if volume.persistent_volume_claim:
                    pvc_key = f"{pod.metadata.namespace}/{volume.persistent_volume_claim.claim_name}"
                    used_pvcs.add(pvc_key)

        # Find orphaned PVCs
        for pvc in pvcs.items:
            pvc_key = f"{pvc.metadata.namespace}/{pvc.metadata.name}"
            if pvc_key not in used_pvcs:
                storage = pvc.spec.resources.requests.get("storage", "unknown")
                self.findings.append({
                    "type": "orphaned_pvc",
                    "severity": "high",
                    "resource": pvc_key,
                    "details": {
                        "storage_requested": storage,
                        "storage_class": pvc.spec.storage_class_name,
                        "phase": pvc.status.phase
                    },
                    "recommendation": "Delete if no longer needed to reduce storage costs"
                })

    def scan_idle_services(self) -> None:
        """Scan for services with no endpoints."""
        print("Scanning for idle services...")

        mlops_namespaces = ["mlops", "mlflow", "kserve"]

        for ns in mlops_namespaces:
            try:
                services = self.v1.list_namespaced_service(ns)
                endpoints = self.v1.list_namespaced_endpoints(ns)

                endpoint_names = {ep.metadata.name for ep in endpoints.items}

                for svc in services.items:
                    if svc.metadata.name not in endpoint_names:
                        self.findings.append({
                            "type": "service_no_endpoints",
                            "severity": "medium",
                            "resource": f"{ns}/{svc.metadata.name}",
                            "details": {
                                "type": svc.spec.type,
                                "ports": [p.port for p in (svc.spec.ports or [])]
                            },
                            "recommendation": "Service has no backends - verify configuration"
                        })
            except client.ApiException:
                continue

    def scan_inference_services(self) -> None:
        """Scan for idle KServe InferenceServices."""
        print("Scanning for idle inference services...")

        try:
            isvc_list = self.custom_api.list_namespaced_custom_object(
                group="serving.kserve.io",
                version="v1beta1",
                namespace="mlops",
                plural="inferenceservices"
            )

            for isvc in isvc_list.get("items", []):
                name = isvc["metadata"]["name"]
                status = isvc.get("status", {})
                conditions = status.get("conditions", [])

                # Check if service is ready but potentially idle
                is_ready = any(
                    c.get("type") == "Ready" and c.get("status") == "True"
                    for c in conditions
                )

                if is_ready:
                    # In production, you'd check actual traffic metrics
                    self.findings.append({
                        "type": "inference_service_review",
                        "severity": "info",
                        "resource": f"mlops/{name}",
                        "details": {
                            "ready": is_ready,
                            "url": status.get("url", "N/A")
                        },
                        "recommendation": "Review traffic metrics to determine if service is utilized"
                    })

        except client.ApiException as e:
            if e.status != 404:
                print(f"Warning: Could not scan InferenceServices: {e}")

    def _generate_report(self) -> Dict[str, Any]:
        """Generate summary report of findings."""
        severity_counts = {"high": 0, "medium": 0, "low": 0, "info": 0}
        for finding in self.findings:
            severity_counts[finding["severity"]] += 1

        # Calculate potential savings estimate
        potential_savings = self._estimate_savings()

        return {
            "scan_timestamp": datetime.utcnow().isoformat(),
            "total_findings": len(self.findings),
            "severity_breakdown": severity_counts,
            "potential_monthly_savings_usd": potential_savings,
            "findings": self.findings
        }

    def _estimate_savings(self) -> float:
        """Estimate potential monthly savings."""
        savings = 0.0

        for finding in self.findings:
            if finding["type"] == "orphaned_pvc":
                # Estimate ~$0.10/GB/month for storage
                storage = finding["details"].get("storage_requested", "0Gi")
                if storage.endswith("Gi"):
                    gb = int(storage[:-2])
                    savings += gb * 0.10

            elif finding["type"] == "overprovisioned_deployment":
                # Estimate ~$30/month per excess replica
                replicas = finding["details"].get("replicas", 0)
                if replicas > 2:
                    savings += (replicas - 2) * 30

        return round(savings, 2)


def main():
    parser = argparse.ArgumentParser(description="Scan for idle MLOps resources")
    parser.add_argument("-n", "--namespace", help="Namespace to scan")
    parser.add_argument("-t", "--threshold", type=int, default=24,
                       help="Hours of inactivity threshold")
    parser.add_argument("-o", "--output", choices=["json", "text"], default="text",
                       help="Output format")
    args = parser.parse_args()

    scanner = IdleResourceScanner(
        namespace=args.namespace,
        idle_threshold_hours=args.threshold
    )

    report = scanner.scan_all()

    if args.output == "json":
        print(json.dumps(report, indent=2))
    else:
        print("\n" + "=" * 60)
        print("IDLE RESOURCE SCAN REPORT")
        print("=" * 60)
        print(f"Scan Time: {report['scan_timestamp']}")
        print(f"Total Findings: {report['total_findings']}")
        print(f"Severity Breakdown: {report['severity_breakdown']}")
        print(f"Estimated Monthly Savings: ${report['potential_monthly_savings_usd']}")
        print("\n" + "-" * 60)

        for finding in report["findings"]:
            print(f"\n[{finding['severity'].upper()}] {finding['type']}")
            print(f"  Resource: {finding['resource']}")
            print(f"  Recommendation: {finding['recommendation']}")


if __name__ == "__main__":
    main()
