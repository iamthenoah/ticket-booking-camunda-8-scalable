# Local Kubernetes Deployment Guide

Run the Ticket Booking system on your local Kubernetes cluster (Docker Desktop or Minikube).

## Prerequisites

### Option 1: Docker Desktop (Recommended)

1. Install [Docker Desktop](https://www.docker.com/products/docker-desktop)
2. Enable Kubernetes:
   - **macOS/Windows**: Preferences → Kubernetes → Enable Kubernetes
   - Restart Docker Desktop
3. Verify: `kubectl cluster-info`

### Option 2: Minikube

```bash
# Install Minikube
brew install minikube

# Start cluster
minikube start --memory=4096 --cpus=4

# Use Minikube's Docker
eval $(minikube docker-env)
```

### Install kubectl

```bash
brew install kubectl
# or use the one bundled with Docker Desktop
```

## Quick Start (5 Steps)

### 1. Build Docker Images Locally

```bash
# Build booking-service
docker build -t booking-service:local ./booking-service-java

# Build fake-services
docker build -t fake-services:local ./fake-services-nodejs

# Verify images exist
docker images | grep -E "booking-service|fake-services"
```

### 2. Create Kubernetes Namespace

```bash
kubectl create namespace ticket-booking
```

### 3. Create Camunda Credentials Secret

Create a `.env.secrets` file with your Camunda credentials:

```bash
cat > .env.secrets << 'EOF'
ZEEBE_ADDRESS=d21e4983-4515-45ef-902d-d7d7309433bf.cdg-1.zeebe.camunda.io:443
ZEEBE_CLIENT_ID=YOUR_CLIENT_ID
ZEEBE_CLIENT_SECRET=YOUR_CLIENT_SECRET
EOF
```

Then create the Kubernetes secret:

```bash
kubectl create secret generic camunda-credentials \
  --from-env-file=.env.secrets \
  -n ticket-booking
```

### 4. Deploy Manifests

```bash
# Deploy namespace, configmap, deployments, and services
kubectl apply -f k8s-local/
```

### 5. Verify Deployment

```bash
# Check pods are running
kubectl get pods -n ticket-booking

# Check services
kubectl get svc -n ticket-booking

# View pod logs
kubectl logs -f deployment/booking-service -n ticket-booking
```

## Local File Structure

The local deployment uses these files:

```
k8s-local/
├── namespace.yaml          # Kubernetes namespace
├── configmap.yaml          # Configuration data
├── deployment.yaml         # Deployments (RabbitMQ, Services)
└── service.yaml            # Services (adjusted for local access)
```

## Accessing Services Locally

### Option 1: Port Forwarding (Recommended for Testing)

```bash
# Access booking-service on localhost:8080
kubectl port-forward svc/booking-service 8080:8080 -n ticket-booking

# Access fake-services on localhost:3000
kubectl port-forward svc/fake-services 3000:3000 -n ticket-booking

# Access RabbitMQ management on localhost:15672
kubectl port-forward svc/rabbitmq 15672:15672 -n ticket-booking
```

Then visit:
- Booking Service: http://localhost:8080
- RabbitMQ: http://localhost:15672 (guest/guest)

### Option 2: NodePort Services (Persistent)

The local deployment uses NodePort services. Get the node port:

```bash
# Get booking-service NodePort
kubectl get svc booking-service -n ticket-booking

# Output shows the port (e.g., 31234)
# Access: http://localhost:31234 (Docker Desktop)
# Access: http://$(minikube ip):31234 (Minikube)
```

### Option 3: Ingress (Advanced)

Enable ingress in Docker Desktop:
- Preferences → Kubernetes → Ingress

Then use the provided ingress manifest.

## Checking Status

### Pod Status

```bash
# List all pods
kubectl get pods -n ticket-booking

# Describe a specific pod for issues
kubectl describe pod <pod-name> -n ticket-booking
```

### Pod Logs

```bash
# Booking service logs
kubectl logs -f deployment/booking-service -n ticket-booking

# Fake services logs
kubectl logs -f deployment/fake-services -n ticket-booking

# RabbitMQ logs
kubectl logs -f deployment/rabbitmq -n ticket-booking
```

### Events

```bash
# See what happened in the namespace
kubectl get events -n ticket-booking --sort-by='.lastTimestamp'
```

### Resource Usage

```bash
# See CPU/memory usage
kubectl top pods -n ticket-booking
kubectl top nodes
```

## Redeploying After Code Changes

### Method 1: Rebuild & Restart (Quickest)

```bash
# Rebuild image
docker build -t booking-service:local ./booking-service-java

# Restart deployment to pull new image
kubectl rollout restart deployment/booking-service -n ticket-booking

# Watch rollout
kubectl rollout status deployment/booking-service -n ticket-booking
```

### Method 2: Use Development Tag

```bash
# Build with dev tag (always latest)
docker build -t booking-service:dev ./booking-service-java

# Update deployment to use :dev
kubectl set image deployment/booking-service \
  booking-service=booking-service:dev \
  -n ticket-booking
```

### Method 3: Hot Reload (for Node.js)

Modify the fake-services deployment to mount your local code:

```yaml
volumeMounts:
- name: code
  mountPath: /app/src
volumes:
- name: code
  hostPath:
    path: /absolute/path/to/fake-services-nodejs/src
    type: Directory
```

Then restart: `kubectl rollout restart deployment/fake-services -n ticket-booking`

## Debugging Common Issues

### Pods Not Starting (CrashLoopBackOff)

```bash
# Check pod status
kubectl describe pod <pod-name> -n ticket-booking

# Check logs for errors
kubectl logs <pod-name> -n ticket-booking

# Common causes:
# - Image not found: ensure docker build succeeded
# - Missing environment variables: check ConfigMap & Secrets
# - Port conflicts: verify services can bind to ports
# - Dependency not ready: check dependent service logs first
```

### Services Not Connecting

```bash
# Test connectivity from within cluster
kubectl run -it debug --image=busybox -n ticket-booking -- sh

# Inside the pod:
wget http://rabbitmq:5672  # Should connect
wget http://fake-services:3000/health  # Check endpoint
exit
```

### Port Forwarding Not Working

```bash
# Kill existing port forwards
lsof -i :8080  # Find process
kill -9 <PID>

# Try again
kubectl port-forward svc/booking-service 8080:8080 -n ticket-booking
```

### Image Pull Issues (Minikube)

Ensure you're using Minikube's Docker daemon:

```bash
eval $(minikube docker-env)
docker build -t booking-service:local ./booking-service-java
```

## Cleanup

### Remove Everything

```bash
# Delete the namespace (removes all resources)
kubectl delete namespace ticket-booking

# Remove local images (optional)
docker rmi booking-service:local fake-services:local
```

### Remove Specific Resources

```bash
# Delete just deployments
kubectl delete deployment -n ticket-booking --all

# Delete just services
kubectl delete svc -n ticket-booking --all

# Delete ConfigMap
kubectl delete configmap ticket-booking-config -n ticket-booking
```

## Scaling

### Scale Booking Service Replicas

```bash
# Scale to 3 replicas
kubectl scale deployment booking-service --replicas=3 -n ticket-booking

# Verify
kubectl get pods -n ticket-booking | grep booking-service
```

## Next Steps: Production (EKS)

When ready to deploy to AWS EKS, follow [K8S_DEPLOYMENT.md](K8S_DEPLOYMENT.md):

1. Push images to AWS ECR
2. Update image references in k8s/deployment.yaml
3. Set up ECR credentials secret
4. Apply manifests to EKS cluster

## Troubleshooting Reference

| Issue | Command to Check |
|-------|------------------|
| Pods stuck "Pending" | `kubectl describe node` |
| Image pull errors | `kubectl describe pod <pod-name>` |
| Network connectivity | `kubectl run debug --image=busybox` |
| Resource exhaustion | `kubectl top pods` |
| Configuration issues | `kubectl get configmap -o yaml` |
| Secret errors | `kubectl get secrets` |

## Resources

- [kubectl Reference](https://kubernetes.io/docs/reference/kubectl/)
- [Docker Desktop Kubernetes](https://docs.docker.com/desktop/features/kubernetes/)
- [Minikube Documentation](https://minikube.sigs.k8s.io/)
- [Kubernetes Tutorials](https://kubernetes.io/docs/tutorials/)
