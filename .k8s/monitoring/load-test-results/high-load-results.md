# High-Load Results

This file records the current `high-load` result and compares it against the low-load baseline in [low-load-baseline.md](./low-load-baseline.md), the scaled medium-load result in [medium-load-results.md](./medium-load-results.md), and the peak-load result in [peak-load-results.md](./peak-load-results.md).

## Run metadata

- Date: `2026-03-14`
- Run ID: `20260314-231658-high-load`
- Scenario: `high-load`
- Scenario file: `load-tests/scenario4-high-load.yml`
- Intended load shape: `60s` at `30 req/s`
- Primary result file: `load-tests/results/20260314-231658-high-load.json`

## Client-facing results

From `load-tests/results/20260314-231658-high-load.json`:

- Total attempted requests: `1800`
- Expected requests: `1800`
- Successful requests: `470`
- Failed requests: `1330`
- Error rate: `73.89%`
- Observed request rate: `30 req/s`
- Mean response time: `5764.7 ms`
- p50 response time: `5826.9 ms`
- p95 response time: `9416.8 ms`
- p99 response time: `9801.2 ms`
- Max response time: `9870 ms`
- Mean session length: `5872.3 ms`
- p95 session length: `9607.1 ms`
- p99 session length: `9801.2 ms`

Failure type:

- `1330` requests failed with `ETIMEDOUT`

## Comparison against low-load, medium-load, and peak-load

Low-load reference:

- Successful requests: `180 / 180`
- Error rate: `0%`
- Mean response time: `759.5 ms`
- p95 response time: `1130.2 ms`
- p99 response time: `1380.5 ms`

Scaled medium-load reference:

- Successful requests: `840 / 840`
- Error rate: `0%`
- Mean response time: `957.6 ms`
- p95 response time: `1495.5 ms`
- p99 response time: `1755 ms`

Scaled peak-load reference:

- Successful requests: `200 / 9000`
- Error rate: `97.78%`
- Mean response time: `5238.3 ms`
- p95 response time: `9230.4 ms`
- p99 response time: `9607.1 ms`

High-load comparison:

- Compared with scaled medium-load:
  - success rate drops from `100%` to `26.11%`
  - error rate rises from `0%` to `73.89%`
  - mean response time rises from `957.6 ms` to `5764.7 ms`
  - p95 rises from `1495.5 ms` to `9416.8 ms`
  - p99 rises from `1755 ms` to `9801.2 ms`
- Compared with scaled peak-load:
  - success rate is much better than peak, but still unacceptable
  - successful-request latency is already in the same near-timeout band as peak

Interpretation:

- `30 req/s` is above the current sustainable throughput of the system
- however, it is still useful as a diagnostic load level because it exposes the bottleneck clearly without collapsing as completely as peak-load
- this run strongly suggests that the sustainable point is somewhere between `14 req/s` and `30 req/s`

## Application bottleneck observations

Use the `Application Bottlenecks` dashboard for this section.

### Booking-level behavior

- Booking end-to-end latency for successful request samples stayed roughly around:
  - p50: `~580-620 ms`
  - p95: `~800-1050 ms`
  - p99: `~900-1350 ms`
- Booking outcomes over time peaked well below the attempted `30 req/s`
- In-flight bookings returned to `0` after the run

Interpretation:

- the successful-sample panels again understate the client-facing collapse
- the Artillery JSON remains the source of truth for absolute successful-request latency under heavy failure
- still, the app-level timing metrics are useful for identifying which internal step dominates

### Java step latency

- `workflow_wait` was clearly the dominant Java-side step
- approximate `workflow_wait` range:
  - p50: `~800-1000 ms`
  - p95: `~580-620 ms` on the successful-sample panel scale, but still visually much larger than the other local steps
- other Java-side steps remained much smaller:
  - `payment_publish`: very small, roughly `~5-10 ms`
  - `payment_correlate`: roughly `~90-110 ms`
  - `payment_wait`: roughly `~160-190 ms`
  - `ticket_http`: roughly `~10-15 ms`

Interpretation:

- the dominant internal measured delay is still the synchronous workflow-completion wait
- no other Java-side local step gets close enough to explain the failure pattern

### Fake-services step latency

- `reserve_seats`: still the largest fake-service step, roughly `~75-100 ms`
- `payment_consume`: stayed low, roughly `~5-10 ms`
- `ticket_http`: stayed low, roughly `~8-12 ms`

Interpretation:

- `fake-services` is not the first bottleneck
- it does not show a timing jump comparable to the client-observed latency collapse

### RabbitMQ behavior

- `paymentRequest` queue depth stayed at `0`
- `paymentResponse` showed one brief spike, peaking around `3`
- no sustained queue growth was visible

Interpretation:

- RabbitMQ is not showing the kind of backlog that would explain the run failure by itself

## Workload-resource observations

Use the `Workload Resources` dashboard for this section.

- `booking-service` ran at `3` replicas and all `3` pods were active
- aggregate booking-service CPU rose across the three pods, with each pod peaking roughly in the `~0.04-0.045 cores` range
- `fake-services` CPU peaked higher than any single booking-service pod, roughly `~0.058 cores`
- `rabbitmq` stayed low, roughly `~0.016 cores`
- booking-service pod memory stayed roughly in the `~235-240 MiB` range
- `fake-services` memory stayed roughly in the `~210 MiB` range
- `rabbitmq` memory stayed around `~122 MiB`

Interpretation:

- all `3` booking-service replicas were actively used
- `fake-services` got busier, but not enough to overturn the timing evidence
- the run does not look like a simple CPU or memory exhaustion story

## Cluster-pressure observations

Use the `Cluster Pressure` dashboard for this section.

- Pending pods: `0`
- Restart rate by pod: `0`
- OOMKilled containers: none observed
- Node CPU rose, with one node reaching roughly `~14-15%`
- Node memory stayed stable, roughly around:
  - node 1: `~45%`
  - node 2: `~39-40%`

Interpretation:

- the cluster itself remained healthy
- the bottleneck stayed inside the application/request path

## Bottleneck conclusion

This run is more informative than simply saying "`30 req/s` is too high."

Clear reasoning:

1. The system sustains `14 req/s` fully after scaling `booking-service` to `3`.
2. The system fails badly at `30 req/s`, but not as catastrophically as at `150 req/s`.
3. `workflow_wait` is still the largest internal measured step.
4. Fake-services stays relatively light in both timing and resources.
5. RabbitMQ does not build sustained backlog.
6. The cluster does not show infrastructure distress.

Conclusion:

- `30 req/s` is above the current sustainable throughput, but the run usefully confirms the same main bottleneck
- the limiting path remains the synchronous workflow-completion wait in `booking-service`
- the value of this run is that it narrows the likely breaking range to somewhere between `14 req/s` and `30 req/s`

## Suggested next step

Use the new ramp scenario next:

- `npm run load:test:ramp`

Why:

- it should identify the break point more precisely than another binary pass/fail test
- it will show whether the transition begins closer to `20 req/s`, `25 req/s`, or `30 req/s`
