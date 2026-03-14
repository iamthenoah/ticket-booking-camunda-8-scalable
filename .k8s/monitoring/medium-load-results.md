# Medium-Load Results

This file records the current medium-load result and compares it against the low-load baseline in [low-load-baseline.md](/c:/Programming/Study/ticket-booking-camunda-8-master/.k8s/monitoring/low-load-baseline.md).

## Run metadata

- Date: `2026-03-14`
- Run ID: `20260314-214650-medium-load`
- Scenario: `medium-load`
- Scenario file: `load-tests/scenario2-medium-load.yml`
- Intended load shape: `60s` at `14 req/s`
- Primary result file: `load-tests/results/20260314-214650-medium-load.json`

## Client-facing results

From `load-tests/results/20260314-214650-medium-load.json`:

- Total attempted requests: `840`
- Expected requests: `840`
- Successful requests: `105`
- Failed requests: `735`
- Error rate: `87.5%`
- Observed request rate: `14 req/s`
- Mean response time: `5288.5 ms`
- p50 response time: `5378.9 ms`
- p95 response time: `9607.1 ms`
- p99 response time: `9801.2 ms`
- Max response time: `9848 ms`
- Mean session length: `5395.3 ms`
- p95 session length: `9607.1 ms`
- p99 session length: `9801.2 ms`

Failure type:

- `735` requests failed with `ETIMEDOUT`

## Comparison against low-load baseline

Low-load reference:

- Successful requests: `180 / 180`
- Error rate: `0%`
- Mean response time: `759.5 ms`
- p95 response time: `1130.2 ms`
- p99 response time: `1380.5 ms`

Medium-load comparison:

- Success-rate change: from `100%` success to `12.5%` success
- Mean latency change: from `759.5 ms` to `5288.5 ms`
- p95 latency change: from `1130.2 ms` to `9607.1 ms`
- p99 latency change: from `1380.5 ms` to `9801.2 ms`
- Main difference in client experience:
  - low-load was stable and fully successful
  - medium-load produced mostly client-side timeouts and near-timeout successful responses

Interpretation:

- the system does not sustain the intended medium-load shape
- the dominant user-visible failure mode is timeout, not HTTP error responses
- latency collapses before any infrastructure saturation is visible

## Application bottleneck observations

Use the `Application Bottlenecks` dashboard for this section.

### Booking-level behavior

- Booking end-to-end latency panel stayed relatively low for the currently observed successful request samples
- Booking outcomes over time showed only successful completions; client-side timeout failures are not directly represented in that panel
- In-flight bookings panel returned to `0`
- No sustained backlog was visible in the currently instrumented app-level gauges

Interpretation:

- the app-level dashboard did not directly expose where the missing `~5-10s` of client wait time accumulated
- the current successful-request panels therefore under-explain the client-facing collapse
- this is why the bottleneck conclusion below is still partly inferred rather than directly measured

### Java step latency

- `payment_publish`: stayed low, roughly `~10-20 ms`
- `payment_correlate`: stayed moderate, roughly `~80-95 ms`
- `payment_wait`: the largest currently measured Java-side step, roughly `~170 ms`
- `ticket_http`: stayed moderate, roughly `~80-95 ms`
- Which Java-side step rose first:
  - `payment_wait` was the largest measured Java-side step, but it was still far too small to explain `~5-10s` client latency on its own

### Fake-services step latency

- `payment_consume`: stayed low, roughly `~5-10 ms`
- `ticket_http`: stayed low, roughly `~8-10 ms`
- `reserve_seats`: stayed modest, roughly `~75 ms` p50 and `~100 ms` p95
- Which fake-services step rose first:
  - no fake-services step showed a large enough jump to explain the medium-load failure pattern

### RabbitMQ behavior

- `paymentRequest` queue depth peak: effectively `0`
- `paymentResponse` queue depth peak: effectively `0`
- Publish vs delivery observations: no clear sustained imbalance was visible
- Was there visible queue buildup:
  - no

### Bottleneck conclusion

- Main bottleneck observed:
  - the strongest current bottleneck is the synchronous workflow-completion path around `booking-service`, not RabbitMQ queue depth, fake-services local processing, or node pressure
- Why:
  - client-side results show severe degradation: `87.5%` timeouts and successful responses clustered around `5-10s`
  - cluster pressure stayed healthy
  - fake-services and RabbitMQ local step metrics stayed small
  - the currently measured Java-side local steps stayed much smaller than the client-observed latency
  - therefore the missing time is most likely being spent in the end-to-end workflow wait/orchestration path rather than in one visible local sub-step

Clear reasoning:

1. The failure is real and severe at the client layer.
2. The cluster is not saturated.
3. RabbitMQ is not building queue backlog.
4. Fake-services is not showing a slow internal stage.
5. The measured Java local steps are not large enough to explain the timeout-heavy response profile.
6. The remaining likely bottleneck is the blocking wait for full workflow completion in `booking-service`.

Important caveat:

- This run did not yet include a direct `workflow_wait` metric around `.withResult().send().join()`.
- So the conclusion above is a strong inference, not direct proof of that exact wait segment.
- A direct `workflow_wait` metric has now been added for future runs to verify this inference explicitly.

## Workload-resource observations

Use the `Workload Resources` dashboard for this section.

- Peak CPU for `booking-service`: `~0.135 cores`
- Peak CPU for `fake-services`: `~0.045 cores`
- Peak CPU for `rabbitmq`: `~0.01 cores`
- Peak memory for `booking-service`: `~215 MiB`
- Peak memory for `fake-services`: `~208 MiB`
- Peak memory for `rabbitmq`: `~123 MiB`
- Replica count changes: none; all stayed at `1`

Interpretation:

- Which workload increased the most:
  - `booking-service`, followed by `fake-services`
- Did resource growth explain the client-side degradation:
  - no; usage rose, but not to a level that would explain `87.5%` timeouts by itself

## Cluster-pressure observations

Use the `Cluster Pressure` dashboard for this section.

- Pending pods: `0`
- Restart rate by pod: `0`
- OOMKilled containers: none observed
- Node CPU range:
  - node 1: roughly `~5.5%` to `7%`
  - node 2: roughly `~3%` to `14%`
- Node memory range:
  - node 1: roughly `~38.3%` to `38.8%`
  - node 2: roughly `~31%` to `32%`

Interpretation:

- Was the cluster itself under pressure:
  - no
- Or did the bottleneck stay inside the application path:
  - yes, the bottleneck stayed inside the application/request path

## Final assessment

- Did the system sustain medium load successfully:
  - no
- If not, where did it fail first:
  - the first obvious failure at the client side was timeout-driven latency collapse
  - the strongest inferred bottleneck is the synchronous workflow-completion wait in `booking-service`
- What should be tested next:
  - rerun `medium-load` with the new direct `workflow_wait` metric in place
  - confirm whether `workflow_wait` becomes the dominant step under load
  - if confirmed, use that as the main architectural bottleneck in the report
