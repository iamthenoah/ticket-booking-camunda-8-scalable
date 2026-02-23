#!/bin/bash

# Setup ECR image pull secret in EKS
# Usage: ./setup-ecr-secret.sh <aws-region> <namespace>

AWS_REGION=${1:-eu-central-1}
NAMESPACE=${2:-ticket-booking}

echo "Setting up ECR image pull secret in namespace: $NAMESPACE"

# Get authorization token
AUTH_TOKEN=$(aws ecr get-authorization-token \
  --region $AWS_REGION \
  --output text \
  --query 'authorizationData[0].authorizationToken')

# Decode to get password
PASSWORD=$(echo $AUTH_TOKEN | base64 -d | cut -d: -f2)

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create secret
kubectl create secret docker-registry ecr-credentials \
  --docker-server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$PASSWORD \
  --docker-email=user@example.com \
  -n $NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ ECR image pull secret created in namespace: $NAMESPACE"
