#!/bin/bash

# Quick setup script for GitHub Actions secrets
# Usage: ./setup-github-secrets.sh

set -e

echo "GitHub Actions Secrets Setup"
echo "============================="
echo ""

# Prompt for values
read -p "Enter AWS Account ID (12 digits): " AWS_ACCOUNT_ID
read -p "Enter AWS Role ARN (github-actions-role): " AWS_ROLE_ARN
read -p "Enter EKS Cluster Name: " EKS_CLUSTER_NAME
read -p "Enter ZEEBE_ADDRESS (from Camunda): " ZEEBE_ADDRESS
read -p "Enter ZEEBE_CLIENT_ID (from Camunda): " ZEEBE_CLIENT_ID
read -p "Enter ZEEBE_CLIENT_SECRET (from Camunda): " ZEEBE_CLIENT_SECRET

echo ""
echo "Setting GitHub secrets..."

# Set secrets using GitHub CLI
gh secret set AWS_ACCOUNT_ID --body "$AWS_ACCOUNT_ID"
gh secret set AWS_ROLE_TO_ASSUME --body "$AWS_ROLE_ARN"
gh secret set EKS_CLUSTER_NAME --body "$EKS_CLUSTER_NAME"
gh secret set ZEEBE_ADDRESS --body "$ZEEBE_ADDRESS"
gh secret set ZEEBE_CLIENT_ID --body "$ZEEBE_CLIENT_ID"
gh secret set ZEEBE_CLIENT_SECRET --body "$ZEEBE_CLIENT_SECRET"
gh secret set ZEEBE_AUTHORIZATION_SERVER_URL --body "https://login.cloud.camunda.io/oauth/token"
gh secret set ZEEBE_TOKEN_AUDIENCE --body "zeebe.camunda.io"

echo ""
echo "✅ All secrets set successfully!"
echo ""
echo "Next steps:"
echo "1. Configure AWS IAM role as described in AWS_SETUP.md"
echo "2. Create ECR repositories: aws ecr create-repository --repository-name ticket-booking-service"
echo "3. Create EKS cluster or use existing one"
echo "4. Push code to trigger the workflow: git push"
