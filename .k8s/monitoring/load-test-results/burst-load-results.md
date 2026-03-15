# Burst-Load Results

This file records the current `burst-load` result and compares it against the scaled medium-load result in [medium-load-results.md](./medium-load-results.md), the threshold-focused ramp result in [ramp-load-results.md](./ramp-load-results.md), and the constant high-load result in [high-load-results.md](./high-load-results.md).

## Run metadata

- Date: `2026-03-14`
- Run ID: `20260314-233223-burst-load`
- Scenario: `burst-load`
- Scenario file: `load-tests/scenario7-burst-load.yml`
- Intended load shape:
  - `60s` at `10 req/s`
  - `30s` spike at `30 req/s`
  - `60s` at `10 req/s`
- Expected requests: `2100`
- Primary result file: `load-tests/results/20260314-233223-burst-load.json`

## Client-facing results

From `load-tests/results/20260314-233223-burst-load.json`:

- Total attempted requests: `2100`
- Successful requests: `1544`
- Failed requests: `556`
- Error rate: `26.48%`
- Mean response time: `2773.3 ms`
- p50 response time: `1130.2 ms`
- p95 response time: `8520.7 ms`
- p99 response time: `9607.1 ms`
- Max response time: `9885 ms`
- Mean session length: `2877.3 ms`
- p95 session length: `8692.8 ms`
- p99 session length: `9607.1 ms`

Failure type:

- `556` requests failed with `ETIMEDOUT`

## Stage-by-stage burst behavior

This scenario is mainly about recovery, not just aggregate pass/fail.

From the per-interval results in `load-tests/results/20260314-233223-burst-load.json`:

- Baseline before the spike: `10 req/s`
  - healthy
  - all requests succeeded
  - mean latency stayed around `~0.79-0.85s`
  - p95 stayed around `~1.13-1.30s`
- Entering the burst:
  - the first elevated interval already pushed mean latency to `~1.44s`
  - p95 rose to `~2.84s`
- During the `30 req/s` burst:
  - first full burst interval still succeeded, but mean latency rose to `~4.57s`
  - next burst interval began timing out: `176` success, `35` timeout
  - final burst-overlap interval was mostly failing: `29` success, `250` timeout
- Recovery after the burst:
  - the first return to `10 req/s` did not recover immediately: `181` timeouts
  - the next interval still had mixed success/failure: `73` success, `70` timeout
  - the next interval improved, but still had `20` timeouts
  - only after that did the system settle back toward normal low-latency behavior

Interpretation:

- the system handles the steady `10 req/s` baseline comfortably
- the `30 req/s` burst is not permanently catastrophic
- however, the burst creates a recovery tail: the system stays overloaded for a while even after the load falls back down

This is the most important property of the burst run:

- the system is spike-sensitive
- but it is not permanently unstable
- recovery takes multiple intervals rather than happening instantly

## Comparison against medium-load, ramp-load, and constant high-load

Scaled medium-load reference at constant `14 req/s`:

- Successful requests: `840 / 840`
- Error rate: `0%`
- Mean response time: `957.6 ms`
- p95 response time: `1495.5 ms`
- p99 response time: `1755 ms`

Ramp-load reference:

- Successful requests: `1215 / 3000`
- Error rate: `59.5%`
- break point identified between `20 req/s` and `30 req/s`

Constant high-load reference at `30 req/s`:

- Successful requests: `470 / 1800`
- Error rate: `73.89%`
- Mean response time: `5764.7 ms`
- p95 response time: `9416.8 ms`
- p99 response time: `9801.2 ms`

Burst-load comparison:

- Compared with scaled medium-load:
  - the system clearly handles low steady load better than the burst path
  - the spike pushes the system into a timeout band that never appears at constant `14 req/s`
- Compared with ramp-load:
  - the burst run is less severe overall because it spends much more time at `10 req/s`
  - but it confirms the same threshold story: once the system is forced near the `30 req/s` region, failures begin
- Compared with constant high-load:
  - the burst run is much healthier overall
  - this means short overloads are survivable in a way that sustained `30 req/s` is not
  - the cost is the delayed recovery tail after the spike

## Application bottleneck observations

Use the `Application Bottlenecks` dashboard for this section.

### Booking-level behavior

- Booking end-to-end latency for successful samples stayed roughly around:
  - p50: `~0.55-0.60s`
  - p95: `~0.75-0.82s`
  - p99: `~0.87-1.15s`
- Booking outcomes over time rose through the baseline, climbed during the burst, then fell again as recovery finished
- In-flight bookings returned to `0` after the run

Interpretation:

- the successful-sample panel again looks much healthier than the Artillery tail latency numbers
- the important reading is not the absolute number on this panel, but which internal step dominates when requests do complete

### Java step latency

- `workflow_wait` remained the dominant Java-side step
- on the successful-sample panel, the `workflow_wait` traces sat well above the other Java steps throughout the run
- the other Java steps stayed much smaller:
  - `payment_publish`: tiny
  - `ticket_http`: small
  - `payment_correlate`: moderate
  - `payment_wait`: larger than the purely local steps, but still well below the overall client-side timeout band

Interpretation:

- the burst run reinforces the same main bottleneck as the other scenarios
- the dominant measured internal delay is still the synchronous wait for workflow completion

### Fake-services step latency

- `reserve_seats` remained the largest fake-service step, around `~75-100 ms`
- `payment_consume` stayed low
- `ticket_http` stayed low

Interpretation:

- `fake-services` still does not look like the first failing stage
- its timing remains relatively flat even while the client-visible burst damage appears

### RabbitMQ behavior

- `paymentRequest` queue depth stayed at `0`
- `paymentResponse` showed only brief small spikes, peaking around `2`
- no sustained queue buildup was visible

Interpretation:

- RabbitMQ still does not show a backlog pattern large enough to explain the run by itself

## Workload-resource observations

Use the `Workload Resources` dashboard for this section.

- `booking-service` stayed at `3` replicas and all `3` pods were active
- booking-service pod CPU rose into the `~0.07-0.08 cores` range during the burst
- `fake-services` CPU peaked around `~0.06 cores`
- `rabbitmq` stayed much lower
- pod memory stayed broadly stable:
  - booking-service pods roughly in the `~238-246 MiB` band
  - `fake-services` roughly around `~200-215 MiB`
  - `rabbitmq` roughly around `~120 MiB`

Interpretation:

- the spike clearly uses the extra `booking-service` replicas
- resource growth is visible, but it still does not look like raw CPU or memory exhaustion

## Cluster-pressure observations

Use the `Cluster Pressure` dashboard for this section.

- Pending pods: `0`
- Restart rate by pod: `0`
- OOMKilled containers: none observed
- Node CPU rose into the mid-to-high teens on one node
- Node memory stayed stable

Interpretation:

- the cluster remained healthy during the spike
- the issue still sits inside the application/request path rather than in node-level capacity

## Bottleneck conclusion

This burst run shows something different from the constant-load tests:

1. The system handles steady `10 req/s` cleanly.
2. The `30 req/s` spike is enough to trigger timeout-driven failure.
3. The system does not recover immediately when load falls back down.
4. `workflow_wait` is still the dominant measured Java-side step.
5. Fake-services and RabbitMQ remain comparatively light.
6. The cluster remains healthy.

Conclusion:

- the same main bottleneck remains in the synchronous workflow-completion wait path in `booking-service`
- the burst run adds one extra insight: overload creates a lingering drain/recovery period
- short spikes above the threshold are survivable, but they still cause a delayed timeout tail after the spike is over

## Suggested next steps

- Keep `medium-soak` as the stability check
  - to confirm whether steady `14 req/s` remains healthy for longer durations
- If the next infrastructure change is scaling `fake-services`, rerun:
  - `burst-load`
  - `ramp-load`

Why:

- `ramp-load` shows where the system breaks
- `burst-load` shows whether the system can absorb and recover from a short overload
