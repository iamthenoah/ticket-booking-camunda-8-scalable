# Changelog (Existing Files Only)

This file documents updates made to files that already existed in the repository.
Newly created files (for example Kubernetes manifests, schema/repository classes, and other new deployment files) are intentionally excluded.

## Java application changes

### `booking-service-java/pom.xml`
- Added `spring-boot-starter-actuator` for health/readiness/liveness endpoints.
- Added `spring-boot-starter-jdbc` for SQL persistence.
- Added PostgreSQL JDBC driver (`org.postgresql:postgresql`).

### `booking-service-java/src/main/resources/application.properties`
- Replaced hardcoded Camunda values with environment-driven placeholders.
- Added `zeebe.client.cloud.authUrl` (from `CAMUNDA_OAUTH_URL` with SaaS default).
- Replaced RabbitMQ host/port/user/pass config with single `RABBITMQ_URL`.
- Added `ticketbooking.payment.endpoint` as env-driven value.
- Added datasource properties for PostgreSQL via env vars.
- Enabled SQL init with `spring.sql.init.mode=always`.
- Enabled actuator probe endpoints for Kubernetes:
  - health probes
  - liveness/readiness state
  - web exposure for `health,info`
- Added graceful shutdown properties:
  - `server.shutdown=graceful`
  - `spring.lifecycle.timeout-per-shutdown-phase=20s`

### `booking-service-java/src/main/java/io/berndruecker/ticketbooking/adapter/GenerateTicketAdapter.java`
- Removed hardcoded Node endpoint constant.
- Added injected property `ticketbooking.payment.endpoint` with default fallback.
- Updated REST call to use injected endpoint.

### `booking-service-java/src/main/java/io/berndruecker/ticketbooking/rest/TicketBookingRestController.java`
- Wired persistence call after workflow completion and before returning `200 OK`.
- Keeps booking result fields unchanged while adding DB write side-effect.

## Node application changes

### `fake-services-nodejs/src/app.ts`
- Added env-driven runtime config:
  - `PORT`
  - `RABBITMQ_URL`
- Replaced hardcoded RabbitMQ connection target with env value.
- Added `GET /health` endpoint for Kubernetes probes.
- Added graceful shutdown handling for `SIGTERM` and `SIGINT`.
- Added shutdown sequence to close:
  - HTTP server
  - Zeebe worker/client
  - RabbitMQ channel/connection

### `fake-services-nodejs/package.json`
- Added `ts-node` dependency for runtime startup command (`npx ts-node ...`).
- Added `typescript` dependency to support TypeScript execution toolchain.

### `fake-services-nodejs/.env`
- Removed committed real credentials and replaced with placeholders.
- Added defaults for:
  - `ZEEBE_TOKEN_AUDIENCE`
  - `RABBITMQ_URL`
  - `PORT`

## Docker and local environment changes

### `docker-compose.yaml`
- Added PostgreSQL service (`postgres:16-alpine`) with healthcheck.
- Made Node service environment fully env-driven (Camunda/Zeebe/RabbitMQ/port).
- Added `RABBITMQ_URL` to Node service env.
- Added Java service env vars for Camunda, RabbitMQ, datasource, and internal ticket endpoint.
- Added `postgres` as dependency for Java service startup ordering.

### `.env.template`
- Reworked template to use placeholder-based, non-secret defaults.
- Added both Camunda-style and Zeebe-style fields used by services.
- Added local defaults for RabbitMQ and PostgreSQL connection values.

### `DOCKER.md`
- Rewritten as concise local development guide.
- Updated setup steps to match `.env.template` and `docker-compose.yaml`.
- Added verification and useful compose commands.

### `.gitignore`
- Added ignore rules for `.env` files to reduce risk of committing secrets.

