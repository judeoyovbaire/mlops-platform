# ADR-006: Argo Workflows Over Kubeflow Pipelines

## Status

Accepted

## Context

The platform needs a workflow orchestration engine for ML training pipelines. The pipeline consists of sequential steps: data loading, validation, feature engineering, model training, and model registration. Key requirements:

- DAG-based workflow execution on Kubernetes
- Artifact passing between steps
- Retry policies and error handling
- Integration with MLflow for experiment tracking
- Minimal operational overhead

The two leading options in the Kubernetes-native ML orchestration space are:
1. **Argo Workflows** (CNCF Graduated project)
2. **Kubeflow Pipelines** (built on top of Argo Workflows)

## Decision

We will use **Argo Workflows** directly for ML pipeline orchestration.

## Consequences

### Positive

- **CNCF Graduated**: Mature project with strong governance, wide adoption, and active community
- **Lightweight**: Single installation via Helm, no complex dependencies
- **General-purpose**: Not ML-specific, which means better documentation and broader community support
- **Native Kubernetes**: WorkflowTemplates are standard Kubernetes CRDs - familiar to any DevOps engineer
- **Rich DAG support**: Native DAG execution with conditional branching, loops, and retry policies
- **Artifact management**: Built-in artifact passing via S3/GCS/MinIO between workflow steps
- **UI included**: Argo Workflows Server provides built-in visualization and management UI

### Negative

- **No ML-specific abstractions**: Lacks Kubeflow's `@component` decorator and Python DSL for pipeline definition
- **YAML-heavy**: Pipelines are defined in YAML rather than Python SDK
- **No experiment tracking**: Must integrate separately with MLflow (vs Kubeflow's built-in metadata store)
- **No notebook integration**: Kubeflow provides Jupyter notebook management out of the box

### Neutral

- Both solutions run containers on Kubernetes with similar resource requirements
- Both support parameterized workflows and cron scheduling

## Alternatives Considered

### Alternative 1: Kubeflow Pipelines

**Pros:**
- Python SDK (`kfp`) for pipeline definition
- Built-in experiment tracking and metadata store
- ML-specific UI with experiment comparison
- Managed versions available (Vertex AI Pipelines, SageMaker Pipelines)

**Cons:**
- Heavy footprint: requires Argo Workflows + MySQL + ML Metadata store + Kubeflow Pipelines API server
- Complex installation and maintenance
- Tightly coupled to Kubeflow ecosystem
- KFP v2 SDK has breaking changes from v1

**Why not chosen:** The operational overhead of running the full Kubeflow Pipelines stack is not justified when we already have MLflow for experiment tracking. Argo Workflows provides the core orchestration capabilities we need with significantly less complexity.

### Alternative 2: Apache Airflow

**Pros:**
- Industry standard for data orchestration
- Rich ecosystem of providers/operators
- Mature Python SDK

**Cons:**
- Not Kubernetes-native (requires separate infrastructure)
- Heavier operational footprint (scheduler, webserver, database, workers)
- Not designed for ML-specific workloads

**Why not chosen:** Airflow is optimized for data engineering workflows, not ML training pipelines. Argo Workflows' Kubernetes-native approach is a better fit.

## References

- [Argo Workflows Documentation](https://argo-workflows.readthedocs.io/)
- [CNCF Argo Project](https://www.cncf.io/projects/argo/)
- [Kubeflow Pipelines Documentation](https://www.kubeflow.org/docs/components/pipelines/)
