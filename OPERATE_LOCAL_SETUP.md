# Camunda Operate Local Setup

This Docker Compose file sets up Camunda Operate locally for self-managed deployments with Zeebe and Elasticsearch.

## What's Included

- **Zeebe 8.8.0** - Workflow automation engine (port 26500)
- **Elasticsearch 7.17.9** - Data store and indexing (port 9200)
- **Camunda Operate 8.8.0** - Web UI for monitoring and managing workflows (port 8080)

## Quick Start

### Start all services:

```bash
docker compose -f docker-compose.operate.yml up --build
```

### Access Operate:

Open your browser and go to:

```
http://localhost:8080
```

**Default credentials:**

- Username: `demo`
- Password: `demo`

## Integrated with Ticket Booking System

To run Operate alongside the ticket booking system:

```bash
# Terminal 1: Start the ticket booking system
docker compose up --build

# Terminal 2: Start Operate (in separate terminal)
docker compose -f docker-compose.operate.yml up
```

Or modify `docker-compose.yml` to include Operate. The services will communicate because:

- Zeebe will export data to Elasticsearch
- Operate queries Elasticsearch for workflow instances and jobs
- Booking service and fake-services connect to this Zeebe instance instead of Camunda Cloud

## Configuration

### Environment Variables

All Operate configuration is set via environment variables:

| Variable                                 | Default                     | Description                             |
| ---------------------------------------- | --------------------------- | --------------------------------------- |
| `camunda.operate.elasticsearch.url`      | `http://elasticsearch:9200` | Elasticsearch endpoint for Operate data |
| `camunda.operate.zeebeElasticsearch.url` | `http://elasticsearch:9200` | Elasticsearch endpoint for Zeebe data   |
| `camunda.operate.zeebe.gatewayAddress`   | `zeebe:26500`               | Zeebe gateway address                   |
| `camunda.operate.cloud.userId`           | `demo`                      | User ID                                 |
| `camunda.operate.cloud.organizationId`   | `camunda`                   | Organization ID                         |

### Port Mappings

| Service             | Internal Port | External Port |
| ------------------- | ------------- | ------------- |
| Zeebe               | 26500         | 26500         |
| Zeebe Management    | 9600          | 9600          |
| Elasticsearch       | 9200          | 9200          |
| Elasticsearch Nodes | 9300          | 9300          |
| Operate             | 8080          | 8080          |

## Connecting Ticket Booking System

Update your booking-service and fake-services to connect to local Zeebe instead of Camunda Cloud:

### In `docker-compose.yml`, update fake-services environment:

```yaml
environment:
  ZEEBE_ADDRESS: zeebe:26500
  ZEEBE_CLIENT_ID: ${ZEEBE_CLIENT_ID}
  ZEEBE_CLIENT_SECRET: ${ZEEBE_CLIENT_SECRET}
  ZEEBE_AUTHORIZATION_SERVER_URL: http://zeebe:8080
  ZEEBE_TOKEN_AUDIENCE: zeebe
```

### In `application.properties`, update booking-service:

```properties
zeebe.client.cloud.region=localhost
zeebe.client.cloud.clusterId=zeebe
zeebe.client.cloud.clientId=zeebe-client
zeebe.client.cloud.clientSecret=
```

## Health Checks

Services have built-in health checks that ensure:

1. Elasticsearch is ready before Zeebe starts
2. Zeebe is ready before Operate starts
3. All services are healthy before accepting requests

Check health status:

```bash
docker compose -f docker-compose.operate.yml ps
```

## Common Tasks

### View Zeebe broker logs:

```bash
docker compose -f docker-compose.operate.yml logs -f zeebe
```

### View Elasticsearch logs:

```bash
docker compose -f docker-compose.operate.yml logs -f elasticsearch
```

### View Operate logs:

```bash
docker compose -f docker-compose.operate.yml logs -f operate
```

### Stop all services:

```bash
docker compose -f docker-compose.operate.yml down
```

### Remove all data (clean slate):

```bash
docker compose -f docker-compose.operate.yml down -v
```

## Troubleshooting

### Operate not starting or shows errors

**Check Elasticsearch is running:**

```bash
curl http://localhost:9200/_cluster/health
```

**Check Zeebe is running:**

```bash
curl http://localhost:9600/health
```

**Check Operate logs:**

```bash
docker compose -f docker-compose.operate.yml logs operate
```

### Cannot connect to Operate on localhost:8080

Wait 60+ seconds for services to fully initialize. Health checks ensure all dependencies are ready.

### Elasticsearch running out of memory

Increase memory allocation in the compose file:

```yaml
environment:
  - 'ES_JAVA_OPTS=-Xms1g -Xmx1g' # Change 512m to 1g
```

### Port conflicts

If ports are already in use, modify the port mappings:

```yaml
ports:
  - '9201:9200' # Use different host port
```

## Performance Tips

1. **Increase Elasticsearch memory** for large process instances:

   ```yaml
   ES_JAVA_OPTS: '-Xms1g -Xmx1g'
   ```

2. **Adjust Zeebe exporter settings** for high-volume deployments:

   ```yaml
   ZEEBE_BROKER_EXPORTERS_ELASTICSEARCH_ARGS_BULK_SIZE: 5000
   ZEEBE_BROKER_EXPORTERS_ELASTICSEARCH_ARGS_BULK_DELAY: 10
   ```

3. **Use named volumes** for persistent data: Already configured with `elasticsearch-data` and `zeebe-data` volumes

## Next Steps

1. Deploy your BPMN process to Zeebe
2. Create process instances from the booking service
3. Monitor instances in Operate UI
4. Analyze workflow performance and logs

## Documentation

- [Camunda Operate Documentation](https://unsupported.docs.camunda.io/1.3/docs/self-managed/operate-deployment/)
- [Zeebe Documentation](https://docs.camunda.io/docs/product-manuals/zeebe/zeebe-overview/)
- [Elasticsearch Documentation](https://www.elastic.co/guide/en/elasticsearch/reference/7.16/index.html)

## Security Notes

⚠️ **This setup is for local development only!**

For production use:

- Enable Elasticsearch security (`xpack.security.enabled=true`)
- Use proper authentication for Zeebe
- Configure HTTPS/TLS
- Set appropriate passwords
- Use environment-based secrets management
- Restrict port access with firewall rules
