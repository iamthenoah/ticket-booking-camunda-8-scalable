# Monitoring Features Guide

This file is the user-friendly overview of the monitoring and observability improvements in this project. It explains what is already implemented today and what is planned next, so you can quickly understand what to use during load testing and troubleshooting.

Dashboards are grouped under Grafana, while some support features live in the load-test scripts, Grafana backup tooling, and service-level metrics instrumentation.

## Implemented

### Feature: Load Test Overview

**Where to find it**

- Grafana dashboard: `Load Test Overview`

**What it is used for**

- Compare load-test runs, see how many requests were attempted, how many failed, and how latency changed over time.

**Example scenario**

- Compare a low-load run against a medium-load or edge-load run and see where errors first appear.
- Written run notes and comparisons live in [`load-test-results/README.md`](./load-test-results/README.md).

**Parts of the feature**

- `Attempt Rate`
  - Shows the actual request-rate line for each selected run and the matching expected-rate line from the scenario definition.
  - `actual <run_id>`: the request rate Artillery actually reached during the run.
  - `expected <run_id>`: the rate the scenario was supposed to produce.
  - If you compare multiple runs at once, the panel shows one actual line and one expected line for each selected run.
- `Latency Percentiles`
  - Shows `p50`, `p95`, and `p99` response-time lines for each selected run.
  - `p50`: the typical request latency.
  - `p95`: the latency of the slower edge of successful requests.
  - `p99`: the extreme tail latency that often shows overload first.
  - If several runs are selected, each percentile is repeated once per run.
- `Successful Requests`
  - Shows one summary value: the total number of successful `2xx` responses in the selected run window.
- `Failed Requests`
  - Shows one summary value: the total number of failed virtual users in the selected run window.
- `Error Rate`
  - Shows one summary value: failed requests as a percentage of all attempted requests.
- `Errors Over Time`
  - Shows when failures happened and which failure types appeared during the run.
  - `errors_<type> <run_id>`: a separate line for each concrete Artillery error type, such as `errors_ETIMEDOUT` or `errors_ECONNRESET`.
  - `total_failed <run_id>`: the overall failed-request line, regardless of error type.
  - If several runs are selected, each error series is repeated per run.
- `Total Attempted Requests`
  - Shows one summary value: the total number of HTTP requests Artillery attempted to send.
- `Expected Requests`
  - Shows one summary value: how many requests the scenario definition expected to send.

**Technologies used**

- Artillery
- Prometheus Pushgateway
- Prometheus
- Grafana
- PowerShell load-test runner

### Feature: Workload Resources

**Where to find it**

- Grafana dashboard: `Workload Resources`

**What it is used for**

- Track per-pod CPU, memory, and replica counts during load tests.

**Example scenario**

- Check whether all `booking-service` replicas are actually being used during medium, high, or ramp tests.

**Parts of the feature**

- `CPU Usage by Pod`
  - Shows one line per pod in the selected workloads.
  - Each line is the CPU usage of a single pod, which lets you see whether load is spread evenly or concentrated on one replica.
- `Memory Working Set by Pod`
  - Shows one line per pod in the selected workloads.
  - Each line is the working-set memory of a single pod, which helps spot memory growth, uneven load distribution, or pods that hold more state than others.
- `Current Replica Count`
  - Shows one line per workload, such as `booking-service`, `fake-services`, or `rabbitmq`.
  - Each line is the currently observed replica count for that workload over time.

**Technologies used**

- kube-state-metrics
- Prometheus
- Grafana

### Feature: Cluster Pressure

**Where to find it**

- Grafana dashboard: `Cluster Pressure`

**What it is used for**

- Check whether the cluster itself is under stress, or whether the bottleneck stays inside the application path.

**Example scenario**

- Confirm that a failing peak-load run is not caused by pending pods, node saturation, or restarts.

**Parts of the feature**

- `Node CPU Usage`
  - Shows one line per Kubernetes node.
  - Each line is the average non-idle CPU usage for that node, which helps show whether one node is carrying most of the load.
- `Node Memory Usage`
  - Shows one line per Kubernetes node.
  - Each line is memory usage for that node, which helps detect whether failures are caused by cluster-wide pressure rather than the application path.
- `Pending Pods`
  - Shows one summary value: how many pods in the selected namespace are pending and not yet scheduled or started.
- `Restart Rate by Pod`
  - Shows one line per pod in the namespace.
  - Each line is the recent restart count for that pod, which helps detect crashing or unstable workloads during a test.
- `OOMKilled Containers`
  - Shows one summary value for containers that were OOM-killed in the selected window.

**Technologies used**

- node-exporter
- kube-state-metrics
- Prometheus
- Grafana

### Feature: Application Bottlenecks

**Where to find it**

- Grafana dashboard: `Application Bottlenecks`

**What it is used for**

- Show where booking time accumulates inside the workflow and supporting services.

**Example scenario**

- Confirm that `workflow_wait` is the dominant Java-side step during medium, high, or peak-style tests.

**Parts of the feature**

- `Booking End-to-End Latency`
  - Shows three lines for successful booking latency seen from the application side.
  - `p50`: the typical successful booking time.
  - `p95`: the slower edge of successful booking time.
  - `p99`: the most extreme successful tail latency.
- `Booking Outcomes Over Time`
  - Shows one line per outcome status returned by the booking metric.
  - In the healthy case you usually mainly see `success`.
  - If more outcomes are instrumented later, they appear as separate status lines here.
- `In-Flight Bookings`
  - Shows one summary value: the total number of bookings currently active inside the service across all booking-service pods.
- `Java Step Latency`
  - Shows timing for the main Java-side steps inside `booking-service`.
  - `workflow_wait`: time spent waiting for the workflow result to come back after the booking request has already been started.
  - `payment_publish`: time spent publishing the payment request into RabbitMQ.
  - `payment_wait`: time spent waiting for the payment response to be observed on the Java side.
  - `payment_correlate`: time spent correlating the payment result back into the workflow.
  - `ticket_http`: time spent making the Java-side HTTP call related to ticket generation.
  - The panel usually shows both `p50` and `p95` lines for each step. If more than one pod is active, the chart still shows one line per metric/step combination because the values are aggregated across parallel booking-service instances.
- `Fake Services Step Latency`
  - Shows timing for the main Node fake-service steps.
  - `reserve_seats`: time spent reserving seats in the fake service.
  - `payment_consume`: time spent consuming and handling the payment message.
  - `ticket_http`: time spent serving the fake ticket-related HTTP step.
  - The panel usually shows both `p50` and `p95` lines for each step. If more than one fake-services pod is active, the values are aggregated across those parallel pods.
- `RabbitMQ Queue Depth`
  - Shows one line per RabbitMQ payment queue.
  - `paymentRequest`: messages waiting in the request queue.
  - `paymentResponse`: messages waiting in the response queue.
  - Rising lines here mean queue backlog is building.
- `RabbitMQ Publish vs Delivery Rate`
  - Shows publish and delivery-rate lines per payment queue.
  - `published <queue>`: how quickly messages are being written into that queue.
  - `delivered <queue>`: how quickly consumers are receiving messages from that queue.
  - If published rises above delivered for a sustained period, backlog is building.
- `App CPU Usage by Pod`
  - Shows one line per application pod from `booking-service` and `fake-services`.
  - Each line is CPU usage for that pod, so you can compare step timing against which pods were actually active.
- `App Memory Working Set by Pod`
  - Shows one line per application pod from `booking-service` and `fake-services`.
  - Each line is the working-set memory for that pod during the same window as the bottleneck charts.

**Technologies used**

- Spring Boot Actuator
- Micrometer
- prom-client
- RabbitMQ Prometheus plugin
- Prometheus
- Grafana

### Feature: Service Metrics Instrumentation

**Where to find it**

- `booking-service`: `/actuator/prometheus`
- `fake-services`: `/metrics`
- `rabbitmq`: port `15692`

**What it is used for**

- Expose timing, in-flight, and queue metrics from the services themselves instead of relying only on node or pod metrics.

**Example scenario**

- Check that `workflow_wait` is much larger than the local payment or ticket-generation steps.

**Parts of the feature**

- Booking request metrics
  - Track end-to-end booking request latency and active requests.
- Booking step metrics
  - Track Java-side steps such as `workflow_wait`, `payment_publish`, `payment_wait`, `payment_correlate`, and `ticket_http`.
- Fake-service step metrics
  - Track `reserve_seats`, `payment_consume`, and `ticket_http` on the Node side.
- RabbitMQ queue metrics
  - Track queue depth and related message flow metrics for the payment queues.

**Technologies used**

- Spring Boot Actuator
- Micrometer
- prom-client
- RabbitMQ Prometheus plugin

### Feature: Load-Test Run Metadata and Annotations

**Where to find it**

- Grafana annotations
- `run_id` and `scenario` variables in the dashboards
- expected-request metrics published alongside the test results

**What it is used for**

- Compare one run against another and isolate a specific run window in Grafana.

**Example scenario**

- Filter Grafana to a single edge-load run and compare its latency and failures against a medium-load run.

**Parts of the feature**

- Start annotation
  - Marks when a load test begins.
- Finish annotation
  - Marks when a load test ends and whether it finished successfully.
- Expected request metrics
  - Publish expected total requests, duration, and average request rate from the scenario definition.
- Run labels
  - Attach `run_id`, `scenario`, `env`, and `git_sha` to the pushed metrics.

**Technologies used**

- Artillery
- Prometheus Pushgateway
- Grafana annotations
- PowerShell load-test runner

### Feature: Grafana State Backup and Restore

**Where to find it**

- Scripts in `scripts/monitoring`
- State files in `.k8s/monitoring/grafana-state/`

**What it is used for**

- Preserve dashboard and folder setup in the AWS Academy environment, especially when Grafana does not have durable storage.

**Example scenario**

- Restore dashboards and folders after the Grafana pod is recreated.

**Parts of the feature**

- Export state
  - Saves folders, dashboards, and datasource metadata to local files.
- Import state
  - Restores the saved Grafana configuration through the Grafana API.
- Auto-restore on port-forward
  - Tries to restore the saved state when a new Grafana pod is detected.

**Technologies used**

- Grafana HTTP API
- PowerShell scripts

## Planned / Not Yet Implemented

### Feature: Distributed Tracing

**Where to find it**

- Future Grafana Tempo or Jaeger trace view

**What it is used for**

- Follow one booking end-to-end across HTTP, workflow, RabbitMQ, and downstream calls.

**Example scenario**

- Investigate one booking that took too long and see exactly which hop consumed most of the time.

**Parts of the feature**

- Trace for the incoming request
- Spans for workflow start and workflow wait
- Spans for RabbitMQ publish and consume
- Spans for downstream HTTP calls

**Technologies used**

- OpenTelemetry
- Grafana Tempo or Jaeger

### Feature: Structured Correlated Logs

**Where to find it**

- Future log backend and Grafana logs view

**What it is used for**

- Search one booking or one failure path using shared correlation IDs.

**Example scenario**

- After a spike in Grafana, open logs for the same booking reference or payment request ID to inspect the failure path.

**Parts of the feature**

- Correlation fields
- Start and finish logs
- Error logs

**Technologies used**

- Structured JSON logging
- Optional Loki, Alloy, or Promtail

### Feature: Alerts and SLO-Style Monitoring

**Where to find it**

- Future Grafana alerting and summary health panels

**What it is used for**

- Detect regressions automatically instead of waiting for manual dashboard checks.

**Example scenario**

- Trigger an alert when `workflow_wait` p95 or timeout rate rises above an agreed threshold.

**Parts of the feature**

- Timeout-rate alerts
- Queue-depth alerts
- Scrape-target alerts
- SLO summary panels

**Technologies used**

- Prometheus alert rules
- Grafana alerting

### Feature: Dependency and Workflow Health Views

**Where to find it**

- Future dedicated health dashboard

**What it is used for**

- Show whether dependencies are healthy and whether the workflow engine is introducing hidden delay or backlog.

**Example scenario**

- Distinguish between service-local delay and workflow/orchestration delay when the client sees timeouts.

**Parts of the feature**

- Zeebe or workflow timing
- Active workflow instances
- Dependency up/down row
- Backlog indicators

**Technologies used**

- Application metrics
- Zeebe-facing instrumentation
- Prometheus
- Grafana
