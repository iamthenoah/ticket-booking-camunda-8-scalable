# EKS Deployment Guide

This guide covers automated deployment of the Ticket Booking system to AWS EKS using GitHub Actions.

## Architecture Overview

```
GitHub (Push)
    ↓
GitHub Actions Workflow
    ├─ Build Docker images
    ├─ Push to AWS ECR
    └─ Deploy to EKS Cluster
         ├─ RabbitMQ
         ├─ Fake Services (Node.js)
         └─ Booking Service (Spring Boot)
```

## Quick Start (5 Steps)

### 1. AWS Setup
See [AWS_SETUP.md](AWS_SETUP.md) for detailed instructions:
- Create ECR repositories
- Create/configure EKS cluster  
- Create GitHub Actions IAM role

### 2. Configure GitHub Secrets
See [GITHUB_SECRETS.md](GITHUB_SECRETS.md):

Quick method:
```bash
chmod +x scripts/setup-github-secrets.sh
./scripts/setup-github-secrets.sh
```

Or manually in GitHub UI: Settings → Secrets and variables → Actions

### 3. Deploy to EKS
First time deployment:
```bash
chmod +x scripts/deploy-to-eks.sh
./scripts/deploy-to-eks.sh ticket-booking-cluster ticket-booking eu-central-1
```

Then push code to trigger automated deployments:
```bash
git push origin main
```

### 4. Verify Deployment
```bash
kubectl get pods -n ticket-booking
kubectl get svc -n ticket-booking
```

### 5. Access Services
```bash
# Get external IP of booking service
kubectl get svc booking-service -n ticket-booking

# Test endpoint
curl http://<EXTERNAL-IP>/ticket
```

## File Structure

```
.
├── .github/workflows/
│   └── deploy-to-eks.yml           # GitHub Actions CI/CD pipeline
├── k8s/
│   ├── namespace.yaml               # Kubernetes namespace
│   ├── configmap.yaml               # Configuration data
│   ├── deployment.yaml              # Deployments (RabbitMQ, Services)
│   └── service.yaml                 # Services (ClusterIP, LoadBalancer)
├── scripts/
│   ├── setup-github-secrets.sh      # Auto-configure GitHub secrets
│   ├── setup-ecr-secret.sh          # Setup ECR pull credentials
│   └── deploy-to-eks.sh             # Manual deployment script
├── AWS_SETUP.md                     # AWS configuration guide
├── GITHUB_SECRETS.md                # GitHub secrets documentation
└── k8s-deployment.md                # This file
```

## GitHub Actions Workflow

The workflow file ([.github/workflows/deploy-to-eks.yml](.github/workflows/deploy-to-eks.yml)) does:

1. **Build Stage** (on all pushes)
   - Checkout code
   - Authenticate with AWS using OIDC
   - Login to ECR
   - Build & push booking-service image
   - Build & push fake-services image

2. **Deploy Stage** (only on main/develop branches)
   - Update kubeconfig
   - Create namespace & secrets
   - Deploy manifests to EKS
   - Wait for rollout completion

## Kubernetes Manifests

### ConfigMap (k8s/configmap.yaml)
Contains non-sensitive configuration:
- RabbitMQ host/port/credentials
- Payment endpoint URL
- Zeebe authorization URLs

### Deployment (k8s/deployment.yaml)
Defines three deployments:
- **RabbitMQ**: 1 replica, port 5672
- **fake-services**: 1 replica, port 3000
- **booking-service**: 2 replicas, port 8080

### Service (k8s/service.yaml)
Exposes services:
- **rabbitmq**: ClusterIP (internal only)
- **fake-services**: ClusterIP (internal only)  
- **booking-service**: LoadBalancer (external access)

## Monitoring & Troubleshooting

### Check pod status
```bash
kubectl get pods -n ticket-booking
kubectl describe pod <pod-name> -n ticket-booking
```

### View logs
```bash
# Booking service
kubectl logs -f deployment/booking-service -n ticket-booking

# Fake services
kubectl logs -f deployment/fake-services -n ticket-booking

# RabbitMQ
kubectl logs -f deployment/rabbitmq -n ticket-booking
```

### Check events
```bash
kubectl get events -n ticket-booking --sort-by='.lastTimestamp'
```

### Test connectivity
```bash
# Port forward to test locally
kubectl port-forward svc/booking-service 8080:80 -n ticket-booking
curl http://localhost:8080/ticket
```

## Scaling

### Scale booking service
```bash
kubectl scale deployment booking-service --replicas=3 -n ticket-booking
```

### Update replicas in manifest
Edit `k8s/deployment.yaml` and change `replicas: 2` to desired count, then:
```bash
kubectl apply -f k8s/deployment.yaml -n ticket-booking
```

## Updates & Rollbacks

### Rolling update (automatic)
Update code and push:
```bash
git push origin main
```
GitHub Actions rebuilds images, pushes to ECR, and triggers rolling update.

### Manual update
Edit image in deployment:
```bash
kubectl set image deployment/booking-service \
  booking-service=YOUR_ACCOUNT_ID.dkr.ecr.eu-central-1.amazonaws.com/ticket-booking-service:new-tag \
  -n ticket-booking
```

### Rollback to previous version
```bash
kubectl rollout undo deployment/booking-service -n ticket-booking
```

## Security Best Practices

1. **Secrets Management**
   - Use GitHub Secrets for sensitive data
   - Secrets are mounted as environment variables
   - Never commit credentials to git

2. **RBAC**
   - Deployments use specific IAM roles
   - ECR credentials limited to specific repositories
   - GitHub Actions uses OIDC (no long-lived keys)

3. **Network**
   - RabbitMQ and fake-services are ClusterIP (internal only)
   - Only booking-service exposed via LoadBalancer
   - Use Network Policies to further restrict traffic

4. **Image Security**
   - Images tagged with commit SHA for traceability
   - Use `imagePullPolicy: Always` to prevent cache attacks
   - Scan images with ECR image scanning

## Cost Optimization

1. **Resource Requests/Limits**
   - Set appropriate CPU/memory limits to prevent waste
   - Replicas auto-scale based on demand (requires HPA)

2. **Instance Types**
   - Use spot instances for non-critical workloads
   - Right-size EC2 nodes for your workload

3. **Cleanup**
   - Remove unused images from ECR
   - Delete old versions of deployments

## Advanced Features (Optional)

### Horizontal Pod Autoscaling (HPA)
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: booking-service-hpa
  namespace: ticket-booking
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: booking-service
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### Ingress for Custom Domain
Replace LoadBalancer service with Ingress for domain routing.

### SSL/TLS
Use AWS Certificate Manager and ALB/NLB with HTTPS.

## Cleanup

Remove all resources:
```bash
# Delete namespace (removes all resources)
kubectl delete namespace ticket-booking

# Delete ECR repositories
aws ecr delete-repository --repository-name ticket-booking-service --force
aws ecr delete-repository --repository-name fake-services --force

# Delete EKS cluster
aws eks delete-cluster --name ticket-booking-cluster

# Delete IAM role
aws iam delete-role --role-name github-actions-role
```

## Support & Documentation

- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [kubectl Documentation](https://kubernetes.io/docs/reference/kubectl/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Camunda Platform 8 Documentation](https://docs.camunda.io/)
