# Ramp-Load Results

This file records the current `ramp-load` result and compares it against the stable scaled medium-load result in [medium-load-results.md](./medium-load-results.md), the threshold-style high-load result in [high-load-results.md](./high-load-results.md), and the peak-load result in [peak-load-results.md](./peak-load-results.md).

## Run metadata

- Date: `2026-03-14`
- Run ID: `20260314-232457-ramp-load`
- Scenario: `ramp-load`
- Scenario file: `load-tests/scenario6-ramp-load.yml`
- Intended load shape:
  - `30s` at `10 req/s`
  - `30s` at `20 req/s`
  - `30s` at `30 req/s`
  - `30s` at `40 req/s`
- Expected requests: `3000`
- Primary result file: `load-tests/results/20260314-232457-ramp-load.json`

## Client-facing results

From `load-tests/results/20260314-232457-ramp-load.json`:

- Total attempted requests: `3000`
- Successful requests: `1215`
- Failed requests: `1785`
- Error rate: `59.5%`
- Mean response time: `3355.2 ms`
- p50 response time: `2322.1 ms`
- p95 response time: `8868.4 ms`
- p99 response time: `9607.1 ms`
- Max response time: `9875 ms`
- Mean session length: `3459.4 ms`
- p95 session length: `8868.4 ms`
- p99 session length: `9607.1 ms`

Failure type:

- `1785` requests failed with `ETIMEDOUT`

## Stage-by-stage threshold behavior

The aggregate result matters less here than the transition between stages.

From the per-interval results in `load-tests/results/20260314-232457-ramp-load.json`:

- `10 req/s`
  - all requests succeeded
  - mean latency stayed around `~0.8-0.9s`
  - p95 stayed around `~1.15-1.47s`
- `20 req/s`
  - requests still succeeded
  - latency already inflated sharply
  - mean rose from `~2.03s` to `~3.59s`
  - p95 rose from `~3.75s` to `~5.60s`
- `30 req/s`
  - this is the tipping zone
  - first interval still completed, but mean latency was already `~5.35s`
  - next interval started timing out: `144` success, `83` timeout
  - next interval nearly collapsed: `9` success, `285` timeout
- `40 req/s`
  - effectively complete failure
  - intervals show only timeouts, no successful response histogram samples

Interpretation:

- the system is healthy at `10 req/s`
- the system still functions at `20 req/s`, but latency is already poor
- the system starts failing materially at `30 req/s`
- the system collapses at `40 req/s`

This is the clearest current estimate of the throughput boundary:

- stable throughput is comfortably above `14 req/s`
- acceptable latency likely tops out somewhere around `20 req/s`
- timeout-driven failure begins between `20 req/s` and `30 req/s`

## Comparison against medium-load, high-load, and peak-load

Scaled medium-load reference:

- Successful requests: `840 / 840`
- Error rate: `0%`
- Mean response time: `957.6 ms`
- p95 response time: `1495.5 ms`
- p99 response time: `1755 ms`

High-load reference at constant `30 req/s`:

- Successful requests: `470 / 1800`
- Error rate: `73.89%`
- Mean response time: `5764.7 ms`
- p95 response time: `9416.8 ms`
- p99 response time: `9801.2 ms`

Scaled peak-load reference at `150 req/s`:

- Successful requests: `200 / 9000`
- Error rate: `97.78%`
- Mean response time: `5238.3 ms`
- p95 response time: `9230.4 ms`
- p99 response time: `9607.1 ms`

Ramp-load comparison:

- Compared with scaled medium-load:
  - ramp-load shows that `14 req/s` is not just a lucky pass; the real degradation starts later
  - however, latency starts worsening significantly before the first timeout appears
- Compared with constant high-load:
  - ramp-load overall looks better because its early `10 req/s` and `20 req/s` stages are still healthy
  - once ramp-load reaches `30 req/s`, it starts matching the same failure pattern seen in constant high-load
- Compared with peak-load:
  - peak remains far beyond capacity
  - ramp-load is much more useful diagnostically because it exposes the break point rather than only the collapse state

## Application bottleneck observations

Use the `Application Bottlenecks` dashboard for this section.

### Booking-level behavior

- Booking end-to-end latency for successful samples rose with each later stage:
  - p50 roughly `~0.57-0.60s`
  - p95 roughly `~0.70-0.80s`
  - p99 roughly `~0.88-1.0s`
- Booking outcomes over time climbed through the early ramp stages and then dropped as failures took over
- In-flight bookings returned to `0` after the run

Interpretation:

- the successful-sample timing panel again looks much healthier than the client-facing Artillery numbers
- that is expected here because failed requests that sit until timeout are not represented the same way as the successful workflow completions
- the panel is still useful for identifying which internal step dominates the successful path

### Java step latency

- `workflow_wait` was again the dominant Java-side step
- approximate `workflow_wait` range on the panel:
  - p50 around `~0.7-0.8s`
  - p95 around `~0.55-0.62s`, still clearly above the other local steps on the successful-sample view
- other Java-side steps remained much smaller:
  - `payment_publish`: very small
  - `ticket_http`: still small
  - `payment_correlate`: moderate
  - `payment_wait`: larger than the purely local steps, but still far below the overall client wait

Interpretation:

- the dominant measured internal delay is still the synchronous workflow-completion wait
- the ramp run reinforces that the problem is not one small local adapter call suddenly becoming slow

### Fake-services step latency

- `reserve_seats` remained the largest fake-service step, roughly `~75-100 ms`
- `payment_consume` stayed low
- `ticket_http` stayed low

Interpretation:

- `fake-services` is still not the first bottleneck
- its timing remains too small and too flat to explain the client-side collapse

### RabbitMQ behavior

- `paymentRequest` queue depth stayed at `0`
- `paymentResponse` showed brief spikes up to about `3`
- no sustained queue buildup was visible

Interpretation:

- RabbitMQ is not showing sustained backlog pressure
- it may contribute small delays, but it is not the main throughput limiter

## Workload-resource observations

Use the `Workload Resources` dashboard for this section.

- `booking-service` stayed at `3` replicas and all `3` pods were active
- all three booking-service pods showed CPU growth through the later stages
- `fake-services` CPU rose too, but stayed in the same general band as the booking-service pods rather than vastly exceeding them
- `rabbitmq` stayed low
- pod memory stayed stable with only modest increases

Interpretation:

- the scale-out to `3` booking-service pods is being used
- the run does not look like a simple per-pod CPU or memory exhaustion event
- resource growth tracks load, but the failure point still appears before infrastructure saturation

## Cluster-pressure observations

Use the `Cluster Pressure` dashboard for this section.

- Pending pods: `0`
- Restart rate by pod: `0`
- OOMKilled containers: none observed
- Node CPU rose into the mid-teens
- Node memory stayed stable

Interpretation:

- the cluster remained healthy
- the bottleneck still sits inside the application request path rather than in raw cluster capacity

## Bottleneck conclusion

This ramp run is the clearest current proof of where the system starts to break.

Clear reasoning:

1. `10 req/s` is healthy.
2. `20 req/s` still succeeds, but latency becomes uncomfortably high.
3. `30 req/s` is the point where timeout-driven failures begin.
4. `40 req/s` is full collapse.
5. `workflow_wait` remains the largest measured Java-side step throughout.
6. Fake-services remains relatively light.
7. RabbitMQ does not show sustained backlog.
8. The cluster itself remains healthy.

Conclusion:

- the current bottleneck is still the synchronous workflow-completion wait in `booking-service`
- the most useful throughput estimate from this run is that the current break point lies between `20 req/s` and `30 req/s`
- if low latency matters, the practical safe ceiling is closer to `20 req/s` than to `30 req/s`

## Suggested next steps

- Run `npm run load:test:burst`
  - to see whether short spikes above the steady-state threshold are survivable
- Run `npm run load:test:soak`
  - to see whether `14 req/s` remains healthy over a longer duration
- If the next infrastructure change is scaling `fake-services`, rerun:
  - `high-load`
  - `ramp-load`

Why:

- those two scenarios are now the most informative threshold tests
- they should show whether the break point moves meaningfully beyond the current `20-30 req/s` range
