# HPA Concept

This note captures a possible autoscaling approach for `booking-service` based on application pressure rather than CPU.

## Why this idea exists

Current load-test results suggest the main bottleneck is not node saturation or RabbitMQ queue growth. The stronger signal is that `booking-service` keeps many requests blocked while waiting for workflow completion.

That makes CPU-based autoscaling a weak fit:

- CPU stayed relatively low even when medium-load and peak-load failed badly
- the limiting factor appears closer to concurrent blocked requests than raw compute usage

## Goal

Scale `booking-service` when it is already holding too many in-flight or blocked requests, instead of waiting for CPU to rise.

## Candidate scaling signals

### Option 1: `ticket_booking_requests_in_flight`

Current status:

- this metric already exists
- it measures how many booking requests are currently in progress

Why it is useful:

- it is the closest current proxy to “the service is busy handling too many simultaneous requests”
- it matches the actual bottleneck shape better than CPU

Possible scaling behavior:

- if average in-flight requests per pod rises above a threshold, add more `booking-service` replicas
- if it stays low for a while, scale back down

What it targets:

- concurrency pressure at the HTTP entry point
- pods that are tied up waiting for workflow completion

### Option 2: `workflow_wait`

Current status:

- a direct `workflow_wait` metric has now been added in code
- it measures the time spent in `.withResult().send().join()`
- it still needs to be deployed before it can be used in decisions

Why it is useful:

- it is a closer representation of the suspected bottleneck than generic in-flight count
- if it rises sharply under load, it directly supports the current bottleneck hypothesis

Possible scaling behavior:

- scale when `workflow_wait` latency or concurrent `workflow_wait` activity stays above a target

What it targets:

- orchestration/wait pressure in the synchronous booking path

### Option 3: timeout or error-rate based signal

Why it is less attractive:

- by the time timeout rate is high, the user experience is already bad
- this is a late signal

Use:

- better as an alerting signal than a primary scaling signal

## Suggested first autoscaling design

Use `booking-service` only.

Metric:

- `ticket_booking_requests_in_flight`

Desired behavior:

- keep average in-flight requests per pod below a chosen threshold
- scale up when blocked concurrency grows
- scale down slowly after load drops

Replica policy concept:

- `minReplicas: 1`
- `maxReplicas: 5`
- scale on average in-flight requests per pod

Why start with this:

- simplest metric because it already exists
- requires no change to business logic
- aligns better with the observed bottleneck than CPU

## Why not scale `fake-services` first

Current evidence does not show `fake-services` as the main first bottleneck:

- fake-services step latencies stayed relatively small
- RabbitMQ queue depth did not build up meaningfully
- `booking-service` is where requests stay blocked waiting for end-to-end completion

Because of that, the cleanest experiment order is:

1. scale `booking-service` first
2. rerun `medium-load`
3. only scale `fake-services` if `booking-service` scaling alone is not enough

## Infrastructure required for this later

This is not a plain built-in HPA setup. Kubernetes HPA does not read arbitrary Prometheus metrics on its own.

Typical options:

- Prometheus Adapter
- KEDA

Either option would expose a custom metric that HPA can consume.

## Recommended next step

For now, use static scaling first:

- set `booking-service` replicas to `3`
- rerun `medium-load`

Reason:

- it is simpler than introducing autoscaling infrastructure immediately
- it gives a cleaner before/after comparison
- if static scaling helps, that strengthens the case for later HPA on an in-flight or workflow-wait metric
