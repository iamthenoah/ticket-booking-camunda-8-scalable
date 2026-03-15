# EKS Load-Test Monitoring

This directory contains the phase 1 monitoring setup for the ticket-booking EKS deployment.

## What gets installed

- `kube-prometheus-stack` for Prometheus, Grafana, kube-state-metrics, node-exporter, and kubelet/cAdvisor scraping
- `prometheus-pushgateway` for Artillery metrics
- Grafana dashboards provisioned from the JSON files in [`dashboards`](./dashboards)
- `ServiceMonitor` objects for Pushgateway, `booking-service`, `fake-services`, and `rabbitmq`
- lightweight app bottleneck metrics from `booking-service` and `fake-services`
- RabbitMQ queue metrics via the built-in `rabbitmq_prometheus` plugin

## Manual prerequisites

You need these tools locally before running the install script:

- `node` `22.13+` for the root monitoring and Artillery tooling
- `aws`
- `helm`
- `kubectl`
- `npm`

The application services keep their own runtime expectations. This Node requirement is only for the root-level monitoring and load-test scripts added in phase 1.

Cluster prerequisites:

- local kubeconfig must target the EKS cluster
- `aws eks update-kubeconfig --name ticket-booking-cluster --region us-east-1`
- the cluster must have at least one usable `StorageClass` for Grafana and Prometheus PVCs
- your Kubernetes permissions must allow cluster-scoped Helm installs and RBAC objects
- the cluster must have spare capacity for Prometheus, Grafana, kube-state-metrics, node-exporter, and Pushgateway

## Install

From the repo root:

```powershell
npm install
npm run monitoring:install
```

If your cluster has no default `StorageClass`, inspect the available ones and pass the name explicitly:

```powershell
kubectl get storageclass
npm run monitoring:install -- -StorageClassName <storage-class-name>
```

If your cluster cannot provision EBS-backed PVCs, use the AWS Academy fallback and run the stack without persistent volumes:

```powershell
npm run monitoring:install -- -DisablePersistence
```

This keeps phase 1 usable for load-test monitoring, but Prometheus history and Grafana state will be lost if those pods are recreated.

The install script:

1. adds and updates the `prometheus-community` Helm repo
2. installs `monitoring-stack` into the `monitoring` namespace
3. installs `pushgateway` into the same namespace
4. applies the dashboard `ConfigMap`s plus the Pushgateway, app, and RabbitMQ `ServiceMonitor` objects
5. prints the Grafana admin credentials and next-step commands

## Local access

Start port-forwards:

```powershell
npm run monitoring:port-forward
```

Default local endpoints:

- Grafana: `http://127.0.0.1:3000`
- Pushgateway: `http://127.0.0.1:9091`

Stop the background port-forwards:

```powershell
npm run monitoring:stop-port-forwards
```

Stopping port-forwards only closes your local tunnels. It does not delete Grafana dashboards or Prometheus metrics by itself.

What is lost in the current AWS Academy fallback:

- if you installed with `-DisablePersistence`, Grafana UI changes and Prometheus history are lost when those pods are recreated
- examples: folder moves in Grafana, ad hoc dashboards created in the UI, annotations stored only in Grafana's database, and scraped history stored only in Prometheus

What is not lost:

- dashboard JSON files already committed under [`dashboards`](./dashboards)
- Artillery result JSON files under `load-tests/results/`
- notes you keep in repo files such as the written load-test notes in [`load-test-results/README.md`](./load-test-results/README.md)

To preserve the current Grafana dashboard and folder configuration to local files, export it:

```powershell
npm run monitoring:export-grafana-state
```

This writes the current Grafana folders, dashboard index, datasources, and full dashboard definitions to `.k8s/monitoring/grafana-state/`.

To restore the saved Grafana state manually:

```powershell
npm run monitoring:import-grafana-state
```

Automatic restore behavior:

- if `.k8s/monitoring/grafana-state/` exists, `npm run monitoring:port-forward` will try to restore the saved Grafana state the first time it sees a new Grafana pod name
- this is meant to reapply dashboard and folder configuration after a Grafana restart or reinstall
- repeated `port-forward` calls against the same Grafana pod will not keep re-importing

Limits of that export:

- it preserves dashboard configuration and folder placement
- it does not preserve Prometheus time-series history
- for long-term metric history, you need either working persistence for Prometheus or a remote metrics backend

Prometheus data:

- exporting Prometheus data is technically possible, but it is not as simple as the Grafana dashboard backup
- with the current `-DisablePersistence` setup, Prometheus uses ephemeral local storage, so history disappears when the pod is recreated
- a real Prometheus backup usually means one of:
  - persistent volumes that actually bind and survive pod recreation
  - a remote metrics backend such as Amazon Managed Prometheus, Thanos, Mimir, or VictoriaMetrics
  - TSDB snapshots copied out of the pod, which are possible but not convenient to restore automatically into this setup
- for this phase, Artillery JSON result files plus Grafana dashboard export are the practical local backup path

## Load-test execution

Run one of the prepared scenarios:

```powershell
npm run load:test:low
npm run load:test:medium
npm run load:test:peak
```

Each run:

- creates a unique `run_id`
- posts start/end annotations to Grafana
- pushes Artillery metrics into Pushgateway with `run_id`, `scenario`, `env`, and `git_sha` labels
- waits one Prometheus scrape interval after the test finishes
- wipes the live Pushgateway cache so later runs do not inherit stale pushed series

The wipe only clears Pushgateway's live cache. Historical samples that Prometheus already scraped remain queryable in Grafana.

Results JSON files are written to `load-tests/results/`.

## Dashboards

For the full user-friendly overview of implemented dashboards, support features, and planned observability improvements, see [monitoring-features.md](./monitoring-features.md).

## What you should see

- Artillery request rate, error rate, and latency trends
- pod and container CPU/memory usage for `booking-service`, `fake-services`, and `rabbitmq`
- booking end-to-end latency, booking outcomes, and in-flight requests
- Java-side step timings for payment publish, payment wait, payment correlate, and ticket HTTP
- fake-service step timings for seat reservation, payment consume, and ticket HTTP
- RabbitMQ queue depth plus publish/delivery rates for `paymentRequest` and `paymentResponse`
- deployment replica counts over time
- node CPU and memory pressure
- pending pods, restarts, and OOM-related signals

## Manual Grafana fallback

If dashboard provisioning fails:

1. log into Grafana through the port-forward
2. confirm the default `Prometheus` datasource exists
3. import these files manually from the repo:
   - [`dashboards/load-test-overview.json`](./dashboards/load-test-overview.json)
   - [`dashboards/workload-resources.json`](./dashboards/workload-resources.json)
   - [`dashboards/cluster-pressure.json`](./dashboards/cluster-pressure.json)
   - [`dashboards/application-bottlenecks.json`](./dashboards/application-bottlenecks.json)

If the datasource is missing, create it manually:

- Type: `Prometheus`
- URL: `http://monitoring-stack-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090`
- Access: `Server`
- Default: `true`

## Suggested execution scenarios

1. Install and inspect:
   - run `npm run monitoring:install`
   - run `npm run monitoring:port-forward`
   - confirm the three dashboards load
2. Low-load baseline:
   - run `npm run load:test:low`
   - confirm flat replica counts and low CPU/memory pressure
3. Medium-load comparison:
   - run `npm run load:test:medium`
   - compare the new `run_id` against the low-load baseline
4. Peak-load stress test:
   - run `npm run load:test:peak`
   - correlate latency and errors with pod and node pressure

For the written baseline and the collected run notes, see [`load-test-results/README.md`](./load-test-results/README.md).
