#!/bin/bash

# Deploy to EKS cluster
# Usage: ./deploy-to-eks.sh <cluster-name> <namespace>

CLUSTER_NAME=${1:-ticket-booking-cluster}
NAMESPACE=${2:-ticket-booking}
AWS_REGION=${3:-eu-central-1}

set -e

echo "Deploying to EKS Cluster: $CLUSTER_NAME"
echo "Namespace: $NAMESPACE"
echo "Region: $AWS_REGION"
echo ""

# Update kubeconfig
echo "Updating kubeconfig..."
aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION

# Create namespace
echo "Creating namespace..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Create secrets
echo "Creating Camunda credentials secrets..."
kubectl create secret generic camunda-credentials \
  --from-literal=ZEEBE_ADDRESS="$ZEEBE_ADDRESS" \
  --from-literal=ZEEBE_CLIENT_ID="$ZEEBE_CLIENT_ID" \
  --from-literal=ZEEBE_CLIENT_SECRET="$ZEEBE_CLIENT_SECRET" \
  --from-literal=ZEEBE_AUTHORIZATION_SERVER_URL="https://login.cloud.camunda.io/oauth/token" \
  --from-literal=ZEEBE_TOKEN_AUDIENCE="zeebe.camunda.io" \
  -n $NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

# Apply manifests
echo "Applying Kubernetes manifests..."
kubectl apply -f k8s/configmap.yaml -n $NAMESPACE
kubectl apply -f k8s/deployment.yaml -n $NAMESPACE
kubectl apply -f k8s/service.yaml -n $NAMESPACE

# Wait for rollout
echo "Waiting for deployments to be ready..."
kubectl rollout status deployment/booking-service -n $NAMESPACE --timeout=5m
kubectl rollout status deployment/fake-services -n $NAMESPACE --timeout=5m

echo ""
echo "✅ Deployment completed successfully!"
echo ""
echo "Check status:"
echo "  kubectl get pods -n $NAMESPACE"
echo "  kubectl get svc -n $NAMESPACE"
