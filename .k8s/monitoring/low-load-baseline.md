# Low-Load Baseline

This document records the first usable low-load baseline for phase 1 monitoring and provides a reference for later `medium-load` and `peak-load` runs.

## Run metadata

- Date: `2026-03-14`
- Run ID: `20260314-173356-low-load`
- Scenario: `low-load`
- Scenario file: `load-tests/scenario1-low-load.yml`
- Intended load shape: `60s` at `3 req/s`
- Time window from Artillery: `17:34:05+0100` to `17:35:09+0100`

## Source of truth

- Use `load-tests/results/20260314-173356-low-load.json` for exact totals and percentiles.
- Use Grafana for trend shape and correlation with workload and cluster metrics.
- Grafana timing can differ slightly from Artillery console timestamps because Prometheus scrapes on an interval and `Request Rate` uses `rate(...)`, which needs multiple scrapes before the first visible point.

## Baseline metrics

From `load-tests/results/20260314-173356-low-load.json`:

- Total requests: `180`
- Successful responses (`200`): `180`
- Failed responses: `0`
- Observed request rate: `3 req/s`
- Mean response time: `803.4 ms`
- p50 response time: `742.6 ms`
- p95 response time: `1380.5 ms`
- p99 response time: `2231 ms`
- Max response time: `2936 ms`
- Mean session length: `907.9 ms`
- p95 session length: `1495.5 ms`
- p99 session length: `2416.8 ms`

## Warm-up note

The first few completed requests were much slower than steady-state traffic.

- First visible Artillery interval had only `6` completed responses
- Mean response time in that first interval: `2245.8 ms`
- p95 in that first interval: `2322.1 ms`

After warm-up, the later intervals settled around:

- mean response time roughly `714 ms` to `743 ms`
- p95 roughly `963 ms` to `1023 ms`

Interpretation:

- the early spike visible in `Load Test Overview` is expected and matches the first Artillery interval
- the later lower-latency points better represent steady-state low-load behavior

## Cluster-pressure observations

From the `Cluster Pressure` dashboard during the actual run window:

- Pending pods: `0`
- Restart rate by pod: `0`
- OOMKilled containers: none observed
- Node CPU after warm-up stayed low, roughly `3%` to `8%` per node
- Node memory stayed stable, roughly `40%` to `41%` on one node and `24%` to `25%` on the other

Interpretation:

- the cluster was not saturated during low-load
- low-load latency was not caused by node pressure, pending pods, or restart churn

## Workload-resource observations

Use the `Workload Resources` dashboard to capture these values for each future run:

- peak CPU for `booking-service`
- peak CPU for `fake-services`
- peak CPU for `rabbitmq`
- peak memory for `booking-service`
- peak memory for `fake-services`
- peak memory for `rabbitmq`

This first baseline run established the dashboards and cluster health successfully, but the exact workload CPU and memory peaks were not written down in this document.

## Comparison template

Use this checklist for `medium-load` and `peak-load` runs:

- Run ID:
- Total requests:
- Successful responses:
- Failed responses:
- Mean response time:
- p95 response time:
- p99 response time:
- Peak CPU for `booking-service`:
- Peak CPU for `fake-services`:
- Peak CPU for `rabbitmq`:
- Peak memory for `booking-service`:
- Peak memory for `fake-services`:
- Peak memory for `rabbitmq`:
- Pending pods:
- Restarts:
- OOMKilled containers:
- Node CPU range:
- Node memory range:
- Main bottleneck observed:

## What to compare against this baseline

- If `p95` or `p99` rises much faster than request rate, look at `Workload Resources` first.
- If workload CPU and memory stay low but latency rises, inspect queueing, network calls, or app-internal behavior in phase 2.
- If pending pods, restarts, or OOMKilled values stop being zero, the issue is no longer just application latency under load.
