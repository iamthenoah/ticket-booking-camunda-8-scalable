# AWS EKS Deployment Setup

Complete guide to deploy the Ticket Booking system to AWS EKS using GitHub Actions and ECR.

## Prerequisites

- AWS Account with permissions to create EKS clusters, ECR repositories, and IAM roles
- GitHub repository with Actions enabled
- `kubectl` configured locally (for testing)
- AWS CLI v2 installed

## Step 1: Configure AWS Account

### 1.1 Create ECR Repositories

```bash
aws ecr create-repository \
  --repository-name ticket-booking-service \
  --region eu-central-1

aws ecr create-repository \
  --repository-name fake-services \
  --region eu-central-1
```

Take note of the repository URIs and your AWS Account ID.

### 1.2 Create EKS Cluster (if not exists)

Using AWS Console or CLI:

```bash
aws eks create-cluster \
  --name ticket-booking-cluster \
  --version 1.27 \
  --roleArn arn:aws:iam::YOUR_ACCOUNT_ID:role/eks-service-role \
  --resourcesVpcConfig subnetIds=subnet-xxx,subnet-yyy \
  --region eu-central-1
```

Or use the AWS CloudFormation template (see below).

### 1.3 Create IAM Role for GitHub Actions

**1. Create trust relationship policy file** (`trust-policy.json`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_ORG/YOUR_REPO:*"
        }
      }
    }
  ]
}
```

**2. Create the IAM role:**

```bash
aws iam create-role \
  --role-name github-actions-role \
  --assume-role-policy-document file://trust-policy.json
```

**3. Create policy file** (`github-actions-policy.json`):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeRepositories"
      ],
      "Resource": [
        "arn:aws:ecr:eu-central-1:YOUR_ACCOUNT_ID:repository/ticket-booking-service",
        "arn:aws:ecr:eu-central-1:YOUR_ACCOUNT_ID:repository/fake-services"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["eks:DescribeCluster", "eks:ListClusters"],
      "Resource": ["arn:aws:eks:eu-central-1:YOUR_ACCOUNT_ID:cluster/ticket-booking-cluster"]
    },
    {
      "Effect": "Allow",
      "Action": ["sts:GetCallerIdentity"],
      "Resource": "*"
    }
  ]
}
```

**4. Attach the policy:**

```bash
aws iam put-role-policy \
  --role-name github-actions-role \
  --policy-name github-actions-policy \
  --policy-document file://github-actions-policy.json
```

Get the role ARN:

```bash
aws iam get-role --role-name github-actions-role --query 'Role.Arn' --output text
```

## Step 2: Configure GitHub Secrets

Add the following secrets to your GitHub repository (Settings > Secrets and variables > Actions):

| Secret Name                      | Value                                                                           |
| -------------------------------- | ------------------------------------------------------------------------------- |
| `AWS_ACCOUNT_ID`                 | Your AWS Account ID (12 digits)                                                 |
| `AWS_ROLE_TO_ASSUME`             | Full ARN of the `github-actions-role` created above                             |
| `EKS_CLUSTER_NAME`               | `ticket-booking-cluster`                                                        |
| `ZEEBE_ADDRESS`                  | From Camunda Platform 8 console (e.g., `cluster-id.cdg-1.zeebe.camunda.io:443`) |
| `ZEEBE_CLIENT_ID`                | From Camunda Platform 8 credentials                                             |
| `ZEEBE_CLIENT_SECRET`            | From Camunda Platform 8 credentials                                             |
| `ZEEBE_AUTHORIZATION_SERVER_URL` | `https://login.cloud.camunda.io/oauth/token`                                    |
| `ZEEBE_TOKEN_AUDIENCE`           | `zeebe.camunda.io`                                                              |

Example in GitHub CLI:

```bash
gh secret set AWS_ACCOUNT_ID --body "123456789012"
gh secret set AWS_ROLE_TO_ASSUME --body "arn:aws:iam::123456789012:role/github-actions-role"
gh secret set EKS_CLUSTER_NAME --body "ticket-booking-cluster"
gh secret set ZEEBE_ADDRESS --body "d21e4983-4515-45ef-902d-d7d7309433bf.cdg-1.zeebe.camunda.io:443"
# ... etc
```

## Step 3: Configure EKS Cluster

### 3.1 Update kubeconfig locally

```bash
aws eks update-kubeconfig \
  --name ticket-booking-cluster \
  --region eu-central-1
```

### 3.2 Create ECR Image Pull Secret (for both services)

```bash
aws ecr get-authorization-token \
  --region eu-central-1 \
  --output text \
  --query 'authorizationData[0].authorizationToken' | base64 -d

# In EKS cluster:
kubectl create namespace ticket-booking

kubectl create secret docker-registry ecr-credentials \
  --docker-server=YOUR_ACCOUNT_ID.dkr.ecr.eu-central-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-authorization-token --region eu-central-1 --output text --query 'authorizationData[0].authorizationToken' | base64 -d | cut -d: -f2) \
  --docker-email=user@example.com \
  -n ticket-booking
```

Or use a script in `scripts/setup-ecr-secret.sh`.

## Step 4: Deploy Manually (First Time)

```bash
# Create namespace
kubectl create namespace ticket-booking

# Create secrets
kubectl create secret generic camunda-credentials \
  --from-literal=ZEEBE_ADDRESS='d21e4983-4515-45ef-902d-d7d7309433bf.cdg-1.zeebe.camunda.io:443' \
  --from-literal=ZEEBE_CLIENT_ID='your-client-id' \
  --from-literal=ZEEBE_CLIENT_SECRET='your-client-secret' \
  --from-literal=ZEEBE_AUTHORIZATION_SERVER_URL='https://login.cloud.camunda.io/oauth/token' \
  --from-literal=ZEEBE_TOKEN_AUDIENCE='zeebe.camunda.io' \
  -n ticket-booking

# Apply configurations
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

# Verify
kubectl get pods -n ticket-booking
kubectl get svc -n ticket-booking
```

## Step 5: Push Code to Trigger CI/CD

Once everything is configured:

```bash
git push origin main
```

This will trigger the GitHub Actions workflow which will:

1. Build Docker images
2. Push to ECR
3. Deploy to EKS automatically

## Monitoring Deployment

### Check deployment status:

```bash
kubectl rollout status deployment/booking-service -n ticket-booking
kubectl rollout status deployment/fake-services -n ticket-booking
```

### View logs:

```bash
kubectl logs -f deployment/booking-service -n ticket-booking
kubectl logs -f deployment/fake-services -n ticket-booking
kubectl logs -f deployment/rabbitmq -n ticket-booking
```

### Get service endpoints:

```bash
kubectl get svc -n ticket-booking

# Get LoadBalancer IP:
kubectl get svc booking-service -n ticket-booking -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

### Port forward for local testing:

```bash
# Access booking service locally
kubectl port-forward svc/booking-service 8080:80 -n ticket-booking

# Access RabbitMQ management
kubectl port-forward svc/rabbitmq 15672:15672 -n ticket-booking
```

## Scaling

### Scale deployments:

```bash
# Scale booking service to 3 replicas
kubectl scale deployment booking-service --replicas=3 -n ticket-booking

# Edit deployment directly
kubectl edit deployment booking-service -n ticket-booking
```

## Troubleshooting

### Images failing to pull:

```bash
# Verify ECR credentials secret exists
kubectl get secret ecr-credentials -n ticket-booking

# Check pod events
kubectl describe pod <pod-name> -n ticket-booking
```

### Deployment not starting:

```bash
# Check pod logs
kubectl logs <pod-name> -n ticket-booking

# Check events
kubectl get events -n ticket-booking --sort-by='.lastTimestamp'
```

### Update image versions:

Edit `k8s/deployment.yaml` and update the image tags, then:

```bash
kubectl apply -f k8s/deployment.yaml -n ticket-booking
```

## Cleanup

To remove everything from EKS:

```bash
kubectl delete namespace ticket-booking
```

To delete the EKS cluster:

```bash
aws eks delete-cluster --name ticket-booking-cluster --region eu-central-1
```

## CloudFormation Template (Optional)

You can use CloudFormation to automate cluster creation. Create `aws/eks-cluster.yaml`:

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: 'EKS Cluster for Ticket Booking Application'

Parameters:
  ClusterName:
    Type: String
    Default: ticket-booking-cluster
  VpcId:
    Type: AWS::EC2::VPC::Id
  SubnetIds:
    Type: List<AWS::EC2::Subnet::Id>

Resources:
  EKSRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: eks.amazonaws.com
            Action: 'sts:AssumeRole'
      ManagedPolicyArns:
        - 'arn:aws:iam::aws:policy/AmazonEKSClusterPolicy'

  EKSCluster:
    Type: AWS::EKS::Cluster
    Properties:
      Name: !Ref ClusterName
      Version: '1.27'
      RoleArn: !GetAtt EKSRole.Arn
      ResourcesVpcConfig:
        SubnetIds: !Ref SubnetIds

  EKSNodeRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: 'sts:AssumeRole'
      ManagedPolicyArns:
        - 'arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy'
        - 'arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy'
        - 'arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly'

Outputs:
  EKSClusterName:
    Value: !Ref EKSCluster
  EKSClusterEndpoint:
    Value: !GetAtt EKSCluster.Endpoint
```

Deploy:

```bash
aws cloudformation create-stack \
  --stack-name ticket-booking-eks \
  --template-body file://aws/eks-cluster.yaml \
  --parameters ParameterKey=ClusterName,ParameterValue=ticket-booking-cluster
```
