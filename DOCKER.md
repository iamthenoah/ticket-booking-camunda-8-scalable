# Docker Setup (Local Development)

Use this when you want to run everything locally without AWS.

## Prerequisites

- Docker Desktop or Docker Engine with Docker Compose v2
- Camunda Platform 8 SaaS account

## Quick Start

1. Copy env template:

```bash
cp .env.template .env
```

2. Fill required Camunda values in `.env`:

- `CAMUNDA_CLUSTER_REGION`
- `CAMUNDA_CLUSTER_ID`
- `CAMUNDA_CLIENT_ID`
- `CAMUNDA_CLIENT_SECRET`
- `CAMUNDA_OAUTH_URL`
- `ZEEBE_ADDRESS`
- `ZEEBE_CLIENT_ID`
- `ZEEBE_CLIENT_SECRET`
- `ZEEBE_AUTHORIZATION_SERVER_URL`

3. Start services:

```bash
docker compose up --build
```

## What Starts

- `rabbitmq` (AMQP + management UI)
- `postgres` (SQL storage for successful bookings)
- `fake-services` (Node.js ticket-generator)
- `booking-service` (Java ticketing-app)

## Endpoints

- Booking API: `http://localhost:8080/ticket`
- RabbitMQ UI: `http://localhost:15672` (`guest` / `guest`)
- Node service: `http://localhost:3000`

## Verify

Book a ticket:

```bash
curl -i -X PUT http://localhost:8080/ticket
```

Simulate failure:

```bash
curl -i -X PUT "http://localhost:8080/ticket?simulateBookingFailure=seats"
curl -i -X PUT "http://localhost:8080/ticket?simulateBookingFailure=ticket"
```

## Useful Commands

```bash
docker compose up -d
docker compose logs -f
docker compose logs -f booking-service
docker compose logs -f fake-services
docker compose down
docker compose down -v
```
