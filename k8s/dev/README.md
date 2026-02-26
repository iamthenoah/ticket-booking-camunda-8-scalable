# Kubernetes Manifests (Dev)

This folder contains the minimum Kubernetes objects required by the EKS deployment workflow.

## Files

- `namespace.yaml`: Creates the `ticket-booking-dev` namespace.
- `configmap.yaml`: Stores non-secret runtime values used by both apps.
- `ticketing-app-deployment.yaml`: Runs the Java Spring Boot service (`ticketing-app`) and enables actuator probes.
- `ticketing-app-service.yaml`: Exposes the Java service with `LoadBalancer` so users can call `PUT /ticket`.
- `ticket-generator-deployment.yaml`: Runs the Node.js worker/API (`ticket-generator`) with `/health` probes.
- `ticket-generator-service.yaml`: Internal `ClusterIP` service used by `ticketing-app`.

## Secrets

No secret values are stored in this folder.  
The GitHub Actions workflow creates/updates the `ticket-booking-secrets` Kubernetes Secret at deploy time.
