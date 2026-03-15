# Medium-Load Results

This file records the current medium-load result and compares it against the low-load baseline in [low-load-baseline.md](./low-load-baseline.md).

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

## Follow-up medium-load run after scaling booking-service to 3 replicas

After the later infrastructure change that increased `booking-service` from `1` to `3` replicas, a new medium-load rerun was executed with the direct `workflow_wait` metric available.

### Run metadata

- Date: `2026-03-14`
- Run ID: `20260314-224753-medium-load`
- Scenario: `medium-load`
- Scenario file: `load-tests/scenario2-medium-load.yml`
- Intended load shape: `60s` at `14 req/s`
- Primary result file: `load-tests/results/20260314-224753-medium-load.json`

### Client-facing results

From `load-tests/results/20260314-224753-medium-load.json`:

- Total attempted requests: `840`
- Expected requests: `840`
- Successful requests: `840`
- Failed requests: `0`
- Error rate: `0%`
- Observed request rate: `14 req/s`
- Mean response time: `957.6 ms`
- p50 response time: `907 ms`
- p95 response time: `1495.5 ms`
- p99 response time: `1755 ms`
- Max response time: `2065 ms`
- Mean session length: `1062.1 ms`
- p95 session length: `1587.9 ms`
- p99 session length: `1863.5 ms`

### Comparison against the earlier medium-load run

Earlier medium-load reference:

- Successful requests: `105 / 840`
- Failed requests: `735 / 840`
- Error rate: `87.5%`
- Mean response time: `5288.5 ms`
- p95 response time: `9607.1 ms`
- p99 response time: `9801.2 ms`

Follow-up medium-load comparison:

- Success-rate change: from `12.5%` success to `100%` success
- Failure-rate change: from `87.5%` to `0%`
- Mean latency change: from `5288.5 ms` to `957.6 ms`
- p95 latency change: from `9607.1 ms` to `1495.5 ms`
- p99 latency change: from `9801.2 ms` to `1755 ms`

Interpretation:

- scaling `booking-service` to `3` replicas materially changed the result
- medium load became sustainable without changing business logic
- the previous failure was therefore strongly tied to concurrency headroom in the synchronous request path rather than to hard cluster saturation

### Application bottleneck observations

Approximate values from the `Application Bottlenecks` dashboard during the run window:

- Booking end-to-end latency stayed roughly around:
  - p50: `~570-580 ms`
  - p95: `~720-780 ms`
  - p99: `~790-880 ms`
- Booking outcomes stayed successful throughout the run window
- In-flight bookings returned to `0` after the run; no sustained backlog was visible

Java-side step timing:

- `workflow_wait` was now directly visible and was clearly the dominant Java-side step
- approximate `workflow_wait` range:
  - p50: `~580 ms`
  - p95: `~720-780 ms`
- other Java-side steps remained much smaller:
  - `payment_publish`: very small, roughly `~5-15 ms`
  - `payment_correlate`: roughly `~80-100 ms`
  - `payment_wait`: roughly `~100-160 ms`
  - `ticket_http`: roughly `~10-15 ms`

Fake-services timing:

- `reserve_seats`: still the largest fake-service step, roughly `~75 ms` p50 and up to `~100-140 ms` p95
- `payment_consume`: stayed low, roughly `~5-10 ms`
- `ticket_http`: stayed low, roughly `~8-12 ms`

RabbitMQ behavior:

- `paymentRequest` queue depth did not build up
- `paymentResponse` showed a short spike, peaking around `6`, but it was not sustained
- no lasting publish/delivery imbalance was visible

### Workload and cluster observations

From the `Workload Resources` and `Cluster Pressure` dashboards:

- `booking-service` now ran at `3` replicas and all `3` pods were active
- booking-service pod CPU rose across all replicas, roughly into the `~0.07-0.10 cores` range per pod
- `fake-services` CPU rose only modestly, roughly to `~0.045 cores`
- `rabbitmq` remained low
- memory increased somewhat across booking-service pods, but stayed moderate
- node CPU rose, but still stayed far from cluster saturation
- pending pods: `0`
- restart rate by pod: `0`
- OOMKilled containers: none observed

### Bottleneck conclusion after scaling

The new direct timing data makes the logic clearer than in the earlier medium-load run:

1. Medium load is now fully successful.
2. The largest measured Java-side step is `workflow_wait`.
3. The other Java-side local steps are much smaller.
4. Fake-services local steps remain relatively small.
5. RabbitMQ shows only a brief, shallow queue spike rather than sustained backlog.
6. The cluster is still healthy.

Interpretation:

- the dominant contributor to request time is now directly visible as `workflow_wait`
- scaling `booking-service` to `3` replicas did not remove that architectural cost, but it gave enough concurrency headroom for the system to sustain medium load successfully
- the main bottleneck hypothesis is therefore confirmed more directly:
  - the key limiting path is the synchronous workflow-completion wait in `booking-service`
- however, at `3` replicas, that bottleneck is no longer severe enough to break `medium-load`
