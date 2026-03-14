# Peak-Load Results

This file records the current peak-load result and compares it against the low-load baseline in [low-load-baseline.md](/c:/Programming/Study/ticket-booking-camunda-8-master/.k8s/monitoring/low-load-baseline.md) and the medium-load result in [medium-load-results.md](/c:/Programming/Study/ticket-booking-camunda-8-master/.k8s/monitoring/medium-load-results.md).

## Run metadata

- Date: `2026-03-14`
- Run ID: `20260314-220200-peak-load`
- Scenario: `peak-load`
- Scenario file: `load-tests/scenario3-peah-load.yml`
- Intended load shape: `60s` at `150 req/s`
- Primary result file: `load-tests/results/20260314-220200-peak-load.json`

## Client-facing results

From `load-tests/results/20260314-220200-peak-load.json`:

- Total attempted requests: `9000`
- Expected requests: `9000`
- Successful requests: `63`
- Failed requests: `8937`
- Error rate: `99.3%`
- Aggregate observed request-rate metric: `65 req/s`
- Mean response time: `5246.6 ms`
- p50 response time: `5168 ms`
- p95 response time: `9230.4 ms`
- p99 response time: `9607.1 ms`
- Max response time: `9873 ms`
- Mean session length: `5354.1 ms`
- p95 session length: `9416.8 ms`
- p99 session length: `9801.2 ms`

Failure types:

- `5892` requests failed with `ETIMEDOUT`
- `3045` requests failed with `ECONNRESET`

Interpretation:

- the system collapses almost immediately at peak load
- the client-side failure mode is now a mix of timeouts and connection resets
- the request-rate metric becomes less trustworthy under this failure pattern; the attempted request count and expected request count are the more reliable top-level indicators

## Comparison against low-load and medium-load

Low-load reference:

- Successful requests: `180 / 180`
- Error rate: `0%`
- Mean response time: `759.5 ms`
- p95 response time: `1130.2 ms`
- p99 response time: `1380.5 ms`

Medium-load reference:

- Successful requests: `105 / 840`
- Error rate: `87.5%`
- Mean response time: `5288.5 ms`
- p95 response time: `9607.1 ms`
- p99 response time: `9801.2 ms`

Peak-load comparison:

- Success-rate change from low-load: from `100%` success to `0.7%` success
- Success-rate change from medium-load: from `12.5%` success to `0.7%` success
- Mean latency change from low-load: from `759.5 ms` to `5246.6 ms`
- Mean latency change from medium-load: roughly unchanged at `~5.2-5.3s`
- p95 latency change from low-load: from `1130.2 ms` to `9230.4 ms`
- p95 latency change from medium-load: slightly lower than medium, but still near the timeout ceiling
- Main difference in client experience:
  - low-load is stable
  - medium-load mostly times out
  - peak-load almost completely fails, with connection resets added on top of timeouts

Interpretation:

- moving from medium to peak does not increase successful-request latency much further; instead it destroys the success rate
- this suggests the system is already saturated by medium-load, and peak-load mostly converts that saturation into near-total failure

## Application bottleneck observations

Use the `Application Bottlenecks` dashboard for this section.

### Booking-level behavior

- Booking end-to-end latency panel for successful samples stayed around:
  - p50: `~600 ms`
  - p95: `~820 ms`
  - p99: `~880 ms`
- Booking outcomes over time showed only successful completions, peaking around `~1.2 req/s`
- In-flight bookings showed a small nonzero value, around `3`
- No large app-level backlog was visible in the currently instrumented gauges

Interpretation:

- the successful-sample panels again understate the client-facing collapse
- the dashboard is mostly showing the minority of requests that still completed successfully
- this means the bottleneck conclusion still has to rely on inference from the mismatch between client-side failure and local app-step measurements

### Java step latency

- `payment_publish`: stayed low, roughly `~5-10 ms`
- `payment_correlate`: stayed moderate, roughly `~95 ms`
- `payment_wait`: the largest currently measured Java-side step, roughly `~160 ms`
- `ticket_http`: stayed moderate, roughly `~80 ms`
- Which Java-side step rose first:
  - `payment_wait` remained the largest measured Java-side step, but still far too small to explain the client-observed failure pattern by itself

### Fake-services step latency

- `payment_consume`: stayed low, roughly `~5-10 ms`
- `ticket_http`: stayed low, roughly `~8-10 ms`
- `reserve_seats`: stayed modest, roughly `~75 ms` p50 and `~100 ms` p95
- Which fake-services step rose first:
  - no fake-services step showed a large enough rise to explain the peak-load collapse

### RabbitMQ behavior

- `paymentRequest` queue depth peak: effectively `0`
- `paymentResponse` queue depth peak: brief spikes to `~2`, later `~1`
- Publish vs delivery observations: no sustained queue growth was visible
- Was there visible queue buildup:
  - no sustained buildup; only tiny transient spikes

### Bottleneck conclusion

- Main bottleneck observed:
  - the strongest current bottleneck is still the synchronous workflow-completion path around `booking-service`, not node capacity, RabbitMQ backlog, or fake-services local processing
- Why:
  - peak-load client-side failure is extreme: `99.3%` failure with both `ETIMEDOUT` and `ECONNRESET`
  - cluster pressure remained modest
  - fake-services and RabbitMQ local step metrics stayed small
  - Java local step metrics still stayed much smaller than the client-observed wait times
  - therefore the missing time is most likely being spent in the end-to-end workflow/orchestration wait path, which the client experiences as timeout or connection collapse

Clear reasoning:

1. The client-side collapse is even worse than medium-load.
2. The cluster is still not resource-saturated.
3. RabbitMQ is not showing meaningful backlog growth.
4. Fake-services is not showing a slow internal stage.
5. The currently measured Java local steps remain too small to explain `~5-10s` waits and widespread connection failure.
6. The remaining likely bottleneck is the blocking wait for full workflow completion in `booking-service`.

Important caveat:

- This run also did not yet include a deployed direct `workflow_wait` metric around `.withResult().send().join()`.
- So the conclusion above is again a strong inference, not direct proof of that exact wait segment.
- A direct `workflow_wait` metric has now been added in code for future runs, but it must still be deployed before it can confirm this explicitly.

## Workload-resource observations

Use the `Workload Resources` dashboard for this section.

- Peak CPU for `booking-service`: `~0.075 cores`
- Peak CPU for `fake-services`: `~0.035 cores`
- Peak CPU for `rabbitmq`: `~0.01 cores`
- Peak memory for `booking-service`: `~224 MiB`
- Peak memory for `fake-services`: `~213 MiB`
- Peak memory for `rabbitmq`: `~123 MiB`
- Replica count changes: none; all stayed at `1`

Interpretation:

- `booking-service` still used the most CPU, followed by `fake-services`
- peak-load failure is not explained by CPU or memory exhaustion inside the cluster
- resource growth remains modest despite near-total client failure

## Cluster-pressure observations

Use the `Cluster Pressure` dashboard for this section.

- Pending pods: `0`
- Restart rate by pod: `0`
- OOMKilled containers: none observed
- Node CPU range:
  - node 1: roughly `~5%` to `6.5%`
  - node 2: roughly `~2.5%` to `10.5%`
- Node memory range:
  - node 1: roughly `~38.4%` to `39%`
  - node 2: roughly `~31.3%` to `32.8%`

Interpretation:

- the cluster itself still did not show a failure pattern
- the bottleneck remained inside the application/request path

## Final assessment

- Did the system sustain peak load successfully:
  - no
- If not, where did it fail first:
  - the first visible failure at the client side was immediate collapse into timeout-heavy behavior
  - at higher pressure, the system also started returning connection resets, indicating a more severe overload state than medium-load
  - the strongest inferred bottleneck remains the synchronous workflow-completion wait in `booking-service`
- What this adds beyond the medium-load result:
  - medium-load was enough to prove the system could not sustain the target throughput
  - peak-load confirms that pushing harder does not expose a different infrastructure bottleneck; it mainly amplifies the same application-path limitation into near-total failure
