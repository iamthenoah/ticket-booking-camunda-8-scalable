# Ticket Booking Example

![Ticket Booking Process](booking-service-java/src/main/resources/ticket-booking.png)

A ticket booking example using:
- Camunda Platform 8 (SaaS)
- RabbitMQ
- Java Spring Boot app (`ticketing-app`)
- Node.js app (`ticket-generator`)
- SQL persistence for successful bookings

Change summary for updated existing files is documented in `changelog.md`.

![Architecture Overview](architecture.png)

## Local Run (Docker Compose)

1. Copy the template and fill your Camunda values:
   ```bash
   cp .env.template .env
   ```
2. Start all services:
   ```bash
   docker compose up --build
   ```
3. Test booking API:
   ```bash
   curl -i -X PUT http://localhost:8080/ticket
   ```

Compose now includes:
- RabbitMQ (`rabbitmq`)
- PostgreSQL (`postgres`)
- Node service (`fake-services`)
- Java service (`booking-service`)

## AWS Deployment Quickstart (Dev Only)

This project now includes:
- Kubernetes manifests in `k8s/dev`
- GitHub Actions workflow in `.github/workflows/deploy-dev-eks.yml`

This setup guide uses region `eu-west-3` (Europe/Paris), which fits a Netherlands-based setup and matches Camunda `cdg-1` latency well.

### 1) Sign in to AWS Console and select region

1. Open `https://console.aws.amazon.com/`.
2. Click `Sign in using root user email`.
3. After sign in, use the region selector in the top-right and choose `Europe (Paris) eu-west-3`.

### 2) Create the shared security group (RDS + Amazon MQ)

1. Open service `EC2`.
2. In left menu, click `Security Groups`.
3. Click `Create security group`.
4. Fill:
   - `Security group name`: `ticket-booking-dev-data-sg`
   - `Description`: `Allow EKS app traffic to RDS and MQ`
   - `VPC`: your default VPC
5. In `Inbound rules`, add:
   - Rule 1: `PostgreSQL`, port `5432`, source `172.31.0.0/16` (or your VPC CIDR)
   - Rule 2: `Custom TCP`, port `5671`, source `172.31.0.0/16` (or your VPC CIDR)
6. Keep outbound default (`All traffic`) and click `Create security group`.

### 3) Create ECR repositories

1. Open service `ECR`.
2. Go to `Private repositories`.
3. Click `Create repository`.
4. Create:
   - `ticket-booking/ticketing-app`
   - `ticket-booking/ticket-generator`

### 4) Create IAM role for EKS cluster

1. Open service `IAM`.
2. Go to `Roles` -> `Create role`.
3. Trusted entity: `AWS service`.
4. Use case: `EKS - Cluster`.
5. Role name: `ticketBookingEKSClusterRole`.
6. Create role and confirm policy `AmazonEKSClusterPolicy` is attached.

### 5) Create IAM role for EKS nodes

1. IAM -> `Roles` -> `Create role`.
2. Trusted entity: `AWS service`.
3. Use case: `EC2`.
4. Attach policies:
   - `AmazonEKSWorkerNodePolicy`
   - `AmazonEC2ContainerRegistryPullOnly`
   - `AmazonEKS_CNI_Policy`
5. Role name: `ticketBookingEKSNodeRole`.
6. Create role.

### 6) Create EKS cluster

1. Open service `EKS`.
2. Go to `Clusters` -> `Add cluster` -> `Create`.
3. Choose `Custom configuration`.
4. Set `Use EKS Auto Mode` to `Off`.
5. Configure:
   - `Name`: `ticket-booking-dev-cluster`
   - `Cluster IAM role`: `ticketBookingEKSClusterRole`
6. Networking:
   - Select your default VPC
   - Select at least 2 subnets in different AZs
   - Keep endpoint access default for dev
7. Observability page:
   - Keep optional observability toggles off for lower cost
8. Add-ons page:
   - Keep `CoreDNS`, `Amazon VPC CNI`, `kube-proxy` enabled
   - Keep optional add-ons off for now
9. Click `Create`.

### 7) Create EKS managed node group

1. Open your cluster `ticket-booking-dev-cluster`.
2. Go to tab `Compute`.
3. Click `Add node group`.
4. Configure:
   - Name: `ticket-booking-dev-ng`
   - Node IAM role: `ticketBookingEKSNodeRole`
5. Compute config:
   - Capacity type: `On-Demand`
   - Instance type: `t3.small`
   - Desired size: `2`
   - Min size: `1`
   - Max size: `2`
6. Create node group and wait until status is `Active`.

### 8) Create Amazon MQ (RabbitMQ)

1. Open service `Amazon MQ`.
2. Click `Create broker`.
3. Engine: `RabbitMQ`.
4. Deployment mode: `Single-instance broker` (cheapest dev option).
5. Configure:
   - Broker name: `ticket-booking-dev-rabbitmq`
   - Username/password: create and save credentials
6. Network:
   - Private access
   - VPC: same VPC as EKS
   - Security group: `ticket-booking-dev-data-sg`
7. Create broker and wait for status `Running`.
8. Copy the broker endpoint for `RABBITMQ_URL`.

### 9) Create RDS PostgreSQL

1. Open service `RDS`.
2. Go to `Databases` -> `Create database`.
3. Choose:
   - `Standard create`
   - Engine: `PostgreSQL`
   - Template: `Dev/Test`
4. Configure:
   - DB instance identifier: `ticket-booking-dev-postgres`
   - Master username: `ticketbooking`
   - Set and save password
5. Connectivity:
   - VPC: same as EKS
   - Public access: `No`
   - VPC security group: `ticket-booking-dev-data-sg`
6. Additional config:
   - Initial database name: `ticketbooking`
7. Create database and wait for status `Available`.
8. Copy endpoint/port for `SPRING_DATASOURCE_URL`.

### 10) Configure GitHub OIDC in IAM

1. Open `IAM` -> `Identity providers` -> `Add provider`.
2. Provider type: `OpenID Connect`.
3. Provider URL: `https://token.actions.githubusercontent.com`.
4. Audience: `sts.amazonaws.com`.
5. Create provider.

### 11) Create GitHub Actions deploy role

1. IAM -> `Roles` -> `Create role`.
2. Trusted entity: `Web identity`.
3. Identity provider: `token.actions.githubusercontent.com`.
4. Audience: `sts.amazonaws.com`.
5. Attach or create a policy with permissions for:
   - ECR push/pull for both repositories
   - `eks:DescribeCluster`
6. Role name: `GitHubActionsEKSDeployRole`.
7. Edit trust policy and restrict `sub` to your repo + deploy branches:
   - `repo:<ORG>/<REPO>:ref:refs/heads/main`
   - `repo:<ORG>/<REPO>:ref:refs/heads/aws_demo`
   Example:
   ```json
   "StringLike": {
     "token.actions.githubusercontent.com:sub": [
       "repo:<ORG>/<REPO>:ref:refs/heads/main",
       "repo:<ORG>/<REPO>:ref:refs/heads/aws_demo"
     ]
   }
   ```

### 12) Grant GitHub role EKS cluster access

1. Open `EKS` -> your cluster -> `Access` tab.
2. If needed, set authentication mode to include EKS API access entries.
3. Click `Create access entry`.
4. Principal: `GitHubActionsEKSDeployRole`.
5. Add access policy: `AmazonEKSClusterAdminPolicy`.
6. Scope: `Cluster`.

### 13) Add GitHub repository secrets

| Secret | Description |
|---|---|
| `AWS_ROLE_TO_ASSUME` | IAM role ARN used by GitHub Actions (OIDC). |
| `AWS_REGION` | AWS region, use `eu-west-3`. |
| `EKS_CLUSTER_NAME` | EKS cluster name, use `ticket-booking-dev-cluster`. |
| `RABBITMQ_URL` | Amazon MQ URL (for example `amqps://user:pass@broker-host:5671`). |
| `SPRING_DATASOURCE_URL` | JDBC URL for RDS PostgreSQL. |
| `SPRING_DATASOURCE_USERNAME` | DB username. |
| `SPRING_DATASOURCE_PASSWORD` | DB password. |
| `ZEEBE_ADDRESS` | Zeebe endpoint (for example `cluster-id.cdg-1.zeebe.camunda.io:443`). |
| `ZEEBE_CLIENT_ID` | Camunda/Zeebe client ID. |
| `ZEEBE_CLIENT_SECRET` | Camunda/Zeebe client secret. |
| `ZEEBE_AUTHORIZATION_SERVER_URL` | OAuth URL (usually `https://login.cloud.camunda.io/oauth/token`). |
| `ZEEBE_TOKEN_AUDIENCE` | Usually `zeebe.camunda.io`. |

Optional compatibility: if you still have old `CAMUNDA_*` secrets, the workflow can still use them as fallback.

### Complete secrets list (required + optional)

Required by the current workflow:

| Secret | Required | Notes |
|---|---|---|
| `AWS_ROLE_TO_ASSUME` | Yes | Must be IAM role ARN, format `arn:aws:iam::<account-id>:role/<role-name>`. |
| `AWS_REGION` | Yes | Use `eu-west-3` (or change all AWS resources + policy ARNs to the same region). |
| `EKS_CLUSTER_NAME` | Yes | Example: `ticket-booking-dev-cluster`. |
| `RABBITMQ_URL` | Yes | Use Amazon MQ AMQP endpoint with credentials. |
| `SPRING_DATASOURCE_URL` | Yes | Format: `jdbc:postgresql://<rds-endpoint>:5432/ticketbooking`. |
| `SPRING_DATASOURCE_USERNAME` | Yes | RDS master username (or app DB user). |
| `SPRING_DATASOURCE_PASSWORD` | Yes | Matching DB password. |
| `ZEEBE_ADDRESS` | Yes | Format: `<cluster-id>.<region>.zeebe.camunda.io:443`. |
| `ZEEBE_CLIENT_ID` | Yes | Camunda API client ID. |
| `ZEEBE_CLIENT_SECRET` | Yes | Camunda API client secret. |
| `ZEEBE_AUTHORIZATION_SERVER_URL` | Yes | Usually `https://login.cloud.camunda.io/oauth/token`. |
| `ZEEBE_TOKEN_AUDIENCE` | Yes | Usually `zeebe.camunda.io`. |

Optional / compatibility:

| Secret | Required | Notes |
|---|---|---|
| `AWS_ACCOUNT_ID` | No | Optional convenience value for building IAM/ECR ARNs manually. |
| `CAMUNDA_CLUSTER_ID` | No | Fallback if `ZEEBE_ADDRESS` is not set. |
| `CAMUNDA_CLUSTER_REGION` | No | Fallback if `ZEEBE_ADDRESS` is not set. |
| `CAMUNDA_CLIENT_ID` | No | Fallback for `ZEEBE_CLIENT_ID`. |
| `CAMUNDA_CLIENT_SECRET` | No | Fallback for `ZEEBE_CLIENT_SECRET`. |
| `CAMUNDA_OAUTH_URL` | No | Fallback for `ZEEBE_AUTHORIZATION_SERVER_URL`. |

Where to get each value:

| Secret | Where to copy from |
|---|---|
| `AWS_ROLE_TO_ASSUME` | IAM -> Roles -> `GitHubActionsEKSDeployRole` -> ARN (role ARN). |
| `AWS_REGION` | AWS top-right region selector (`eu-west-3`). |
| `EKS_CLUSTER_NAME` | EKS -> Clusters -> your cluster name. |
| `RABBITMQ_URL` | Amazon MQ -> Broker -> `Endpoints` (AMQP) + broker username/password. |
| `SPRING_DATASOURCE_URL` | RDS -> Databases -> Connectivity -> endpoint, build JDBC URL. |
| `SPRING_DATASOURCE_USERNAME` | RDS -> DB credentials (master username). |
| `SPRING_DATASOURCE_PASSWORD` | Password set during RDS creation. |
| `ZEEBE_ADDRESS` | Camunda Console -> Cluster details -> Zeebe/gRPC endpoint. |
| `ZEEBE_CLIENT_ID` | Camunda Console -> API client credentials. |
| `ZEEBE_CLIENT_SECRET` | Camunda Console -> API client credentials. |
| `ZEEBE_AUTHORIZATION_SERVER_URL` | Camunda OAuth URL (usually `https://login.cloud.camunda.io/oauth/token`). |
| `ZEEBE_TOKEN_AUDIENCE` | Usually `zeebe.camunda.io`. |

### AWS setup gotchas we discovered

1. `AWS_ROLE_TO_ASSUME` must be the IAM role ARN, not the EKS access entry ARN.
2. In IAM JSON policies, replace `ACCOUNT_ID` placeholders with your real 12-digit account ID.
3. Do not rename repository paths inside policy ARNs unless your ECR repo names are different.g
4. OIDC trust policy `sub` must use full refs, for example:
   - `repo:iamthenoah/ticket-booking-camunda-8-master:ref:refs/heads/main`
   - `repo:iamthenoah/ticket-booking-camunda-8-master:ref:refs/heads/aws_demo`
5. Branch patterns like `[main, aws_demo]` are invalid in `sub`; use separate full entries.
6. Amazon MQ `RABBITMQ_URL` should come from broker `Endpoints -> AMQP` and include username/password you set when creating the broker.
7. If Amazon MQ only shows default VPC/subnet options in dev setup, using default VPC/subnet is acceptable.
8. For low-cost dev RDS, use `Dev/Test`, `Single-AZ DB instance deployment`, and smallest available burstable class in your region.
9. Keep AWS region consistent everywhere (ECR, EKS, RDS, MQ, IAM policy ARNs, GitHub secret `AWS_REGION`).

### 14) Deploy flow (automatic)

On every push to `main` or `aws_demo`, GitHub Actions does:
1. Build Docker images for Java and Node.
2. Push both images to ECR with tag = commit SHA.
3. Connect to EKS.
4. Create/update Kubernetes Secret from GitHub Secrets.
5. Apply manifests from `k8s/dev`.
6. Update Deployment images and wait for rollout.
7. Print the booking endpoint URL (LoadBalancer hostname/IP).

## What Each Runtime Variable Means

| Variable | Used by | Meaning |
|---|---|---|
| `ZEEBE_ADDRESS` | Node + pipeline | Zeebe gRPC endpoint (`<cluster>.<region>.zeebe.camunda.io:443`). |
| `ZEEBE_CLIENT_ID` | Java + Node + pipeline | Client ID used for Camunda auth. |
| `ZEEBE_CLIENT_SECRET` | Java + Node + pipeline | Client secret used for Camunda auth. |
| `ZEEBE_AUTHORIZATION_SERVER_URL` | Node + pipeline | OAuth token endpoint for Camunda. |
| `ZEEBE_TOKEN_AUDIENCE` | Node + pipeline | Token audience, usually `zeebe.camunda.io`. |
| `CAMUNDA_CLUSTER_ID` | Java (derived by pipeline) | Derived from `ZEEBE_ADDRESS` and injected for Java Spring config. |
| `CAMUNDA_CLUSTER_REGION` | Java (derived by pipeline) | Derived from `ZEEBE_ADDRESS` and injected for Java Spring config. |
| `CAMUNDA_OAUTH_URL` | Java (fallback/override) | OAuth token endpoint for Java Camunda client (defaults to Camunda SaaS URL). |
| `RABBITMQ_URL` | Java + Node | RabbitMQ connection URL. |
| `SPRING_DATASOURCE_URL` | Java | JDBC URL for SQL DB. |
| `SPRING_DATASOURCE_USERNAME` | Java | DB username. |
| `SPRING_DATASOURCE_PASSWORD` | Java | DB password. |
| `TICKETBOOKING_PAYMENT_ENDPOINT` | Java | Internal URL of the Node ticket API. |
| `PORT` | Node | HTTP port for Node service. |

## Health and Verification

After deployment:
1. Get service URL:
   ```bash
   kubectl get svc ticketing-app -n ticket-booking-dev
   ```
2. Check Java readiness:
   ```bash
   curl http://<LOAD_BALANCER_HOST>/actuator/health/readiness
   ```
3. Check booking endpoint:
   ```bash
   curl -i -X PUT http://<LOAD_BALANCER_HOST>/ticket
   ```
4. Check Node health (from cluster):
   ```bash
   kubectl run curl --image=curlimages/curl:8.6.0 -it --rm --restart=Never -- \
     curl http://ticket-generator.ticket-booking-dev.svc.cluster.local:3000/health
   ```

## How SQL Saving Works

- Table: `ticket_bookings`
- Created automatically from `booking-service-java/src/main/resources/schema.sql`
- One row is inserted for each successful `PUT /ticket` result.

Example query:
```sql
SELECT booking_reference_id, reservation_id, payment_confirmation_id, ticket_id, created_at
FROM ticket_bookings
ORDER BY created_at DESC;
```

## Rollback (Simple)

If latest deploy has issues:

```bash
kubectl rollout undo deployment/ticketing-app -n ticket-booking-dev
kubectl rollout undo deployment/ticket-generator -n ticket-booking-dev
```

Then verify rollout:
```bash
kubectl rollout status deployment/ticketing-app -n ticket-booking-dev
kubectl rollout status deployment/ticket-generator -n ticket-booking-dev
```

## Important Security Note

This repository previously had committed credentials. Those values were removed from tracked config files. Rotate old Camunda credentials and use only GitHub Secrets / Kubernetes Secrets going forward.

## Future Improvements (Not Included Yet)

1. Add a `prod` namespace and a manual approval step in GitHub Actions.
2. Add Helm charts so environment-specific values are easier to manage.
3. Add a smoke test step in CI before the deploy job starts.
4. Replace `schema.sql` initialization with Flyway migrations.
5. Add simple CloudWatch alarms for pod restarts and rollout failures.
