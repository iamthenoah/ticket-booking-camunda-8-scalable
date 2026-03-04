# Kustomization overlay for production deployments

This directory contains Kustomize configurations for different environments. Use this when you want environment-specific overrides.

## Usage

```bash
# Deploy development environment
kubectl apply -k overlays/dev

# Deploy staging environment
kubectl apply -k overlays/staging

# Deploy production environment
kubectl apply -k overlays/production
```

## Example: Create overlays/prod/kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ticket-booking-prod

bases:
  - ../../k8s

patchesStrategicMerge:
  - deployment-patch.yaml

replicas:
  - name: booking-service
    count: 3
  - name: fake-services
    count: 2

configMapGenerator:
  - name: camunda-config
    behavior: merge
    literals:
      - CAMUNDA_CLUSTER_REGION=prod-1
```

See Kustomize documentation: https://kustomize.io/
