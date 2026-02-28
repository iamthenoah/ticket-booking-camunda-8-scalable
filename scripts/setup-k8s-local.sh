#!/bin/bash

set -e

echo "================================"
echo "Local Kubernetes Setup Script"
echo "================================"
echo ""

# Check prerequisites
echo "Checking prerequisites..."
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl or use Docker Desktop."
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Please install Docker Desktop or Docker."
    exit 1
fi

echo "✅ Prerequisites found"
echo ""

# Verify cluster is accessible
echo "Verifying Kubernetes cluster..."
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Kubernetes cluster not accessible."
    echo "   Please enable Kubernetes in Docker Desktop or start Minikube."
    exit 1
fi
echo "✅ Kubernetes cluster ready"
echo ""

# Build images
echo "Building Docker images..."
echo "  → Building booking-service:local..."
docker build -t booking-service:local ./booking-service-java

echo "  → Building fake-services:local..."
docker build -t fake-services:local ./fake-services-nodejs

echo "✅ Images built successfully"
echo ""

# Create namespace
echo "Creating namespace..."
kubectl create namespace ticket-booking --dry-run=client -o yaml | kubectl apply -f -
echo "✅ Namespace created"
echo ""

# Create secrets
echo "Creating Camunda credentials secret..."
if kubectl get secret camunda-credentials -n ticket-booking &> /dev/null; then
    echo "  → Secret already exists, skipping..."
else
    echo "  → Please provide your Camunda credentials:"
    read -p "  ZEEBE_ADDRESS: " ZEEBE_ADDRESS
    read -p "  ZEEBE_CLIENT_ID: " ZEEBE_CLIENT_ID
    read -sp "  ZEEBE_CLIENT_SECRET: " ZEEBE_CLIENT_SECRET
    echo ""
    
    kubectl create secret generic camunda-credentials \
      --from-literal=ZEEBE_ADDRESS="$ZEEBE_ADDRESS" \
      --from-literal=ZEEBE_CLIENT_ID="$ZEEBE_CLIENT_ID" \
      --from-literal=ZEEBE_CLIENT_SECRET="$ZEEBE_CLIENT_SECRET" \
      -n ticket-booking
    echo "✅ Secret created"
fi
echo ""

# Deploy manifests
echo "Deploying manifests..."
kubectl apply -f k8s-local/namespace.yaml
kubectl apply -f k8s-local/configmap.yaml
kubectl apply -f k8s-local/deployment.yaml
kubectl apply -f k8s-local/service.yaml
echo "✅ Manifests deployed"
echo ""

# Wait for deployments
echo "Waiting for deployments to be ready..."
kubectl rollout status deployment/rabbitmq -n ticket-booking --timeout=2m || true
kubectl rollout status deployment/fake-services -n ticket-booking --timeout=2m || true
kubectl rollout status deployment/booking-service -n ticket-booking --timeout=2m || true
echo "✅ Deployments updated"
echo ""

# Show status
echo "================================"
echo "Deployment Status"
echo "================================"
echo ""
echo "Pods:"
kubectl get pods -n ticket-booking
echo ""
echo "Services:"
kubectl get svc -n ticket-booking
echo ""

# Get booking service node port
BOOKING_PORT=$(kubectl get svc booking-service -n ticket-booking -o jsonpath='{.spec.ports[0].nodePort}')

echo "================================"
echo "✅ Setup Complete!"
echo "================================"
echo ""
echo "Services running in the 'ticket-booking' namespace:"
echo ""
echo "  Booking Service:"
echo "    Local:   http://localhost:$BOOKING_PORT"
echo "    Or use:  kubectl port-forward svc/booking-service 8080:8080"
echo ""
echo "  Fake Services (Node.js):"
echo "    Internal: http://fake-services:3000"
echo "    Debug:    kubectl port-forward svc/fake-services 3000:3000"
echo ""
echo "  RabbitMQ:"
echo "    Internal: amqp://rabbitmq:5672"
echo "    Management: kubectl port-forward svc/rabbitmq 15672:15672"
echo "    Then visit: http://localhost:15672 (guest/guest)"
echo ""
echo "Helpful commands:"
echo "  View logs:          kubectl logs -f deployment/booking-service -n ticket-booking"
echo "  Describe pod:       kubectl describe pod <pod-name> -n ticket-booking"
echo "  Port forward:       kubectl port-forward svc/booking-service 8080:8080 -n ticket-booking"
echo "  Check events:       kubectl get events -n ticket-booking --sort-by='.lastTimestamp'"
echo "  Scale deployment:   kubectl scale deployment booking-service --replicas=3 -n ticket-booking"
echo "  Restart deployment: kubectl rollout restart deployment/booking-service -n ticket-booking"
echo "  Delete all:         kubectl delete namespace ticket-booking"
echo ""
