# Docker Setup for Ticket Booking System

This project uses Docker Compose (v2) to run the ticket booking system with all its components.

## Prerequisites

- Docker Desktop or Docker Engine with Docker Compose V2
- Camunda Platform 8 SaaS account (https://camunda.io/)

## Quick Start

### 1. Configure Camunda Platform 8 Credentials

Copy the environment template and fill in your credentials:

```bash
cp .env.template .env
```

Edit `.env` and add your Camunda Platform 8 credentials:

- Login to https://camunda.io/
- Create a new cluster or use an existing one
- Create API client credentials
- Copy the credentials into the `.env` file

### 2. Start All Services

```bash
docker compose up --build
```

This will start:

- **RabbitMQ** on ports 5672 (AMQP) and 15672 (Management UI)
- **Fake Services** (Node.js) on port 3000
- **Booking Service** (Java) on port 8080

### 3. Access the Services

- **Booking Service API**: http://localhost:8080
- **RabbitMQ Management UI**: http://localhost:15672 (guest/guest)
- **Fake Services**: http://localhost:3000

## Testing

Book a ticket:

```bash
curl -i -X PUT http://localhost:8080/ticket
```

Simulate booking failures:

```bash
# Simulate seat reservation failure
curl -i -X PUT http://localhost:8080/ticket?simulateBookingFailure=seats

# Simulate ticket generation failure
curl -i -X PUT http://localhost:8080/ticket?simulateBookingFailure=ticket
```

## Docker Commands

Start services in the background:

```bash
docker compose up -d
```

View logs:

```bash
docker compose logs -f
docker compose logs -f booking-service
docker compose logs -f fake-services
```

Stop services:

```bash
docker compose down
```

Rebuild after code changes:

```bash
docker compose up --build
```

Clean up everything (including volumes):

```bash
docker compose down -v
```

## Architecture

```
┌──────────────────┐
│  Booking Service │ :8080
│  (Spring Boot)   │
└────────┬─────────┘
         │
         ├──── HTTP ────► Fake Services :3000 (Ticket Generation)
         │
         ├──── AMQP ────► RabbitMQ :5672 (Payment)
         │
         └──── gRPC ────► Camunda Platform 8 SaaS

┌──────────────────┐
│  Fake Services   │ :3000
│  (Node.js)       │
└────────┬─────────┘
         │
         ├──── AMQP ────► RabbitMQ :5672 (Payment Service)
         │
         └──── gRPC ────► Camunda Platform 8 SaaS (Seat Reservation)
```

## Troubleshooting

**Services fail to connect to RabbitMQ:**

- Wait for RabbitMQ to be fully started (healthcheck in place)
- Check logs: `docker compose logs rabbitmq`

**Cannot connect to Camunda Platform 8:**

- Verify credentials in `.env` file
- Ensure cluster is running in Camunda Platform 8 console
- Check network connectivity

**Port conflicts:**

- Ensure ports 3000, 5672, 8080, and 15672 are not in use
- Modify port mappings in `compose.yaml` if needed

## Development

To run individual services locally while using Docker for dependencies:

```bash
# Start only RabbitMQ
docker compose up rabbitmq

# Run Node.js service locally
cd fake-services-nodejs
npm install
ts-node src/app.ts

# Run Java service locally
mvn package exec:java -f booking-service-java/
```
