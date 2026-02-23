# GitHub Actions Secrets Template

## Required Secrets for CI/CD Pipeline

Add these to your GitHub repository: Settings → Secrets and variables → Actions

### AWS Configuration
```
AWS_ACCOUNT_ID=123456789012
AWS_ROLE_TO_ASSUME=arn:aws:iam::123456789012:role/github-actions-role
EKS_CLUSTER_NAME=ticket-booking-cluster
```

### Camunda Platform 8 Credentials
```
ZEEBE_ADDRESS=d21e4983-4515-45ef-902d-d7d7309433bf.cdg-1.zeebe.camunda.io:443
ZEEBE_CLIENT_ID=your-client-id-from-camunda
ZEEBE_CLIENT_SECRET=your-client-secret-from-camunda
ZEEBE_AUTHORIZATION_SERVER_URL=https://login.cloud.camunda.io/oauth/token
ZEEBE_TOKEN_AUDIENCE=zeebe.camunda.io
```

## Getting Your Values

### AWS Account ID
```bash
aws sts get-caller-identity --query Account --output text
```

### AWS Role ARN
After creating the IAM role:
```bash
aws iam get-role --role-name github-actions-role --query 'Role.Arn' --output text
```

### Camunda Credentials
Login to https://camunda.io/ → Your Cluster → Copy your Connection Information

## Setting Secrets via GitHub CLI

```bash
gh secret set AWS_ACCOUNT_ID --body "123456789012"
gh secret set AWS_ROLE_TO_ASSUME --body "arn:aws:iam::123456789012:role/github-actions-role"
gh secret set EKS_CLUSTER_NAME --body "ticket-booking-cluster"
gh secret set ZEEBE_ADDRESS --body "d21e4983-4515-45ef-902d-d7d7309433bf.cdg-1.zeebe.camunda.io:443"
gh secret set ZEEBE_CLIENT_ID --body "your-client-id"
gh secret set ZEEBE_CLIENT_SECRET --body "your-client-secret"
gh secret set ZEEBE_AUTHORIZATION_SERVER_URL --body "https://login.cloud.camunda.io/oauth/token"
gh secret set ZEEBE_TOKEN_AUDIENCE --body "zeebe.camunda.io"
```

Or use the setup script:
```bash
chmod +x scripts/setup-github-secrets.sh
./scripts/setup-github-secrets.sh
```
