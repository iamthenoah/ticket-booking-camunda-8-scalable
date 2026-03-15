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

## Follow-up peak-load run after scaling booking-service to 3 replicas

After the later infrastructure change that increased `booking-service` from `1` to `3` replicas, a new peak-load rerun was executed with the direct `workflow_wait` metric available.

### Run metadata

- Date: `2026-03-14`
- Run ID: `20260314-225825-peak-load`
- Scenario: `peak-load`
- Scenario file: `load-tests/scenario3-peah-load.yml`
- Intended load shape: `60s` at `150 req/s`
- Primary result file: `load-tests/results/20260314-225825-peak-load.json`

### Client-facing results

From `load-tests/results/20260314-225825-peak-load.json`:

- Total attempted requests: `9000`
- Expected requests: `9000`
- Successful requests: `200`
- Failed requests: `8800`
- Error rate: `97.78%`
- Aggregate observed request-rate metric: `128 req/s`
- Mean response time: `5238.3 ms`
- p50 response time: `5378.9 ms`
- p95 response time: `9230.4 ms`
- p99 response time: `9607.1 ms`
- Max response time: `9755 ms`
- Mean session length: `5342.1 ms`
- p95 session length: `9416.8 ms`
- p99 session length: `9801.2 ms`

Failure type:

- `8800` requests failed with `ETIMEDOUT`

### Comparison against the earlier peak-load run

Earlier peak-load reference:

- Successful requests: `63 / 9000`
- Failed requests: `8937 / 9000`
- Error rate: `99.3%`
- Failure types: `5892 ETIMEDOUT`, `3045 ECONNRESET`
- Mean response time: `5246.6 ms`
- p95 response time: `9230.4 ms`
- p99 response time: `9607.1 ms`

Follow-up peak-load comparison:

- Success-rate change: from `0.7%` success to `2.22%` success
- Failure-rate change: from `99.3%` to `97.78%`
- Mean latency change for successful requests: effectively unchanged
- p95 and p99 latency for successful requests: effectively unchanged
- Failure-mode change:
  - earlier peak-load mixed `ETIMEDOUT` and `ECONNRESET`
  - follow-up peak-load still failed heavily, but primarily as `ETIMEDOUT`

Interpretation:

- scaling `booking-service` to `3` replicas helped somewhat at peak load, but not enough to make the scenario sustainable
- the main effect was a modest increase in completions, not a meaningful reduction in successful-request latency
- this suggests the same dominant bottleneck remains, but peak pressure still overwhelms the available concurrency headroom

### Application bottleneck observations

Approximate values from the `Application Bottlenecks` dashboard during the run window:

- Booking end-to-end latency for successful request samples stayed roughly around:
  - p50: `~600 ms`
  - p95: `~950 ms`
  - p99: `~1050 ms`
- Booking outcomes over time only reflect the small stream of successful completions
- In-flight bookings returned to `0` after the run

Java-side timing:

- `workflow_wait` was directly visible and was clearly the dominant Java-side step
- approximate `workflow_wait` range:
  - p50: `~600 ms`
  - p95: `~950-1000 ms`
- other Java-side steps remained much smaller:
  - `payment_publish`: very small, roughly `~5-10 ms`
  - `payment_correlate`: roughly `~90-110 ms`
  - `payment_wait`: roughly `~170-190 ms`
  - `ticket_http`: roughly `~10-15 ms`

Fake-services timing:

- `reserve_seats`: still the largest fake-service step, roughly `~75 ms` p50 and up to `~145 ms` p95
- `payment_consume`: stayed low, roughly `~5-10 ms`
- `ticket_http`: stayed low, roughly `~8-12 ms`

RabbitMQ behavior:

- `paymentRequest` queue depth stayed at `0`
- `paymentResponse` showed brief spikes, peaking around `6`, then dropping again
- no sustained queue growth was visible

### Workload and cluster observations

From the `Workload Resources` and `Cluster Pressure` dashboards:

- `booking-service` ran at `3` replicas and all `3` pods were active
- booking-service pod CPU rose across all replicas, roughly into the `~0.10-0.13 cores` range per pod
- `fake-services` CPU rose materially as well, roughly to `~0.08 cores`
- `rabbitmq` stayed comparatively low
- booking-service pod memory rose into roughly the `~245-252 MiB` range
- node CPU increased further than in the earlier peak run, with one node reaching roughly `~25%`
- node memory also rose, but still without cluster distress
- pending pods: `0`
- restart rate by pod: `0`
- OOMKilled containers: none observed

### Bottleneck conclusion after scaling

The new direct timing data makes the peak-load picture clearer:

1. Peak load is still not sustainable.
2. `workflow_wait` is the largest measured Java-side step.
3. The other Java-side local steps remain much smaller.
4. Fake-services gets busier, and `reserve_seats` rises somewhat, but still not enough to explain the full client-side collapse.
5. RabbitMQ shows brief response-queue spikes, but not sustained backlog.
6. The cluster still does not show an infrastructure failure pattern.

Interpretation:

- the main architectural bottleneck remains the synchronous workflow-completion wait in `booking-service`
- scaling `booking-service` to `3` replicas improves peak-load throughput somewhat, but only modestly
- peak load still overwhelms the current design, so the scenario remains dominated by timeout-heavy failure even though the same change was enough to make medium-load fully successful

Important timing note:

- there is still a large mismatch between client-observed successful-request latency in `Load Test Overview` (`~5-10s`) and the app-level successful-request timing visible in `Application Bottlenecks` (`~0.6-1.0s`)
- that means the app-step panels are useful for bottleneck direction, but the Artillery JSON remains the source of truth for absolute client latency under heavy failure conditions
