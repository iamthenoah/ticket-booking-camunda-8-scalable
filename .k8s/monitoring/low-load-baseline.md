# Low-Load Baseline

This file records the current low-load reference run to compare against `medium-load` and `peak-load`.

## Run metadata

- Date: `2026-03-14`
- Run ID: `20260314-213612-low-load`
- Scenario: `low-load`
- Scenario file: `load-tests/scenario1-low-load.yml`
- Intended load shape: `60s` at `3 req/s`
- Primary result file: `load-tests/results/20260314-213612-low-load.json`

## Source of truth

- Use the Artillery JSON file for exact request totals and latency percentiles.
- Use Grafana for bottleneck, workload, and cluster correlations.
- Use this run as the main low-load reference for later comparisons.

## Client-facing baseline metrics

From `load-tests/results/20260314-213612-low-load.json`:

- Total attempted requests: `180`
- Successful responses (`200`): `180`
- Failed responses: `0`
- Observed request rate: `3 req/s`
- Mean response time: `759.5 ms`
- p50 response time: `742.6 ms`
- p95 response time: `1130.2 ms`
- p99 response time: `1380.5 ms`
- Max response time: `1751 ms`
- Mean session length: `866.3 ms`
- p95 session length: `1249.1 ms`
- p99 session length: `1495.5 ms`

## Warm-up note

This run still had a slower first interval, but it was much cleaner than the earlier low-load run.

- First visible Artillery interval completed `21` responses
- First-interval mean response time: `894.7 ms`
- First-interval p95: `1525.7 ms`

Interpretation:

- there is still a small warm-up effect
- the run settles quickly into steady-state behavior
- this run is a better low-load reference than the earlier warm-up-heavy run

## Application bottleneck observations

Approximate values from the `Application Bottlenecks` dashboard during the run window:

- Booking end-to-end latency stayed roughly around:
  - p50: `~450-510 ms`
  - p95: `~800 ms`
  - p99: `~870-920 ms`
- Booking outcomes showed only `success`
- In-flight bookings returned to `0` after the run; no sustained buildup was visible
- Java-side step latency stayed low:
  - `payment_publish`: `~5-7 ms`
  - `payment_correlate`: `~75-80 ms`
  - `payment_wait`: `~90 ms`
  - `ticket_http`: `~90-95 ms`
- Fake-services step latency stayed low:
  - `payment_consume`: `~5-7 ms`
  - `ticket_http`: `~8-10 ms`
  - `reserve_seats`: `~75 ms` p50 and `~100 ms` p95
- RabbitMQ queue depth stayed at `0` almost the entire time, with one brief `paymentResponse` spike to `1`
- No clear application-stage bottleneck was visible at low load

## Workload-resource observations

Approximate values from the `Workload Resources` dashboard during the run window:

- Peak CPU for `booking-service`: `~0.08 cores`
- Peak CPU for `fake-services`: `~0.015 cores`
- Peak CPU for `rabbitmq`: `~0.005 cores`
- Peak memory for `booking-service`: `~199 MiB`
- Peak memory for `fake-services`: `~202 MiB`
- Peak memory for `rabbitmq`: `~123 MiB`
- Replica count stayed at `1` for all workloads

Interpretation:

- `booking-service` used the most CPU, but still very little in absolute terms
- `fake-services` and `rabbitmq` stayed light
- low-load behavior was not resource-limited

## Cluster-pressure observations

Approximate values from the `Cluster Pressure` dashboard during the run window:

- Pending pods: `0`
- Restart rate by pod: `0`
- OOMKilled containers: none observed
- Node CPU stayed low, roughly:
  - node 1: `~5%` to `6%`
  - node 2: `~2.5%` to `9%`
- Node memory stayed stable, roughly:
  - node 1: `~38%` to `38.5%`
  - node 2: `~30%` to `31%`

Interpretation:

- the cluster was healthy during the run
- the low-load baseline was not limited by infrastructure pressure

## Baseline summary

Use this as the main low-load reference:

- `180 / 180` succeeded
- `0` failures
- mean latency `759.5 ms`
- p95 `1130.2 ms`
- p99 `1380.5 ms`
- no visible queue buildup
- no sustained in-flight backlog
- no cluster pressure
- no clear bottleneck at low load

## Follow-up low-load run after scaling booking-service to 3 replicas

After the later infrastructure change that increased `booking-service` from `1` to `3` replicas, a new low-load rerun was inspected through the `Application Bottlenecks` and `Workload Resources` dashboards.

What changed operationally:

- `booking-service` replica count increased from `1` to `3`
- `fake-services` remained at `1`
- `rabbitmq` remained at `1`
- the new `workflow_wait` Java-side metric was available

What stayed the same:

- low load still completed cleanly
- there was no visible cluster pressure
- there was still no meaningful RabbitMQ backlog
- `fake-services` step latency stayed small

What became clearer:

- the new `workflow_wait` metric was the largest Java-side step even under low load
- local Java work such as `payment_publish`, `payment_wait`, `payment_correlate`, and `ticket_http` remained much smaller
- `fake-services` still looked light, so the main delay did not move downstream

Interpretation:

- scaling `booking-service` to `3` did not reveal a new bottleneck at low load
- instead, it strengthened the earlier hypothesis that the dominant time in the request path is spent waiting for workflow completion
- this does not mean low load is unhealthy; the run still looked stable
- it does mean the most important latency component is now directly visible, and it sits in the synchronous workflow-completion path rather than in cluster pressure, RabbitMQ buildup, or fake-service processing

Why this matters for the next medium-load comparison:

- if `workflow_wait` rises sharply while the other Java and fake-service steps remain comparatively small, that is strong evidence that scaling improved concurrency headroom but did not remove the main architectural bottleneck
- if, instead, one fake-service step starts rising materially after scaling `booking-service`, that would suggest the bottleneck shifted downstream
