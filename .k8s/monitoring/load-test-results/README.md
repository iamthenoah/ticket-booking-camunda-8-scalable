# Load-Test Results Notes

This directory groups the written notes for the load-test runs that were analyzed in Grafana and compared against the raw Artillery JSON files in `load-tests/results/`.

Use these notes when you want the human-readable interpretation of a run, not just the raw request totals and latency numbers.

## Files

- [low-load-baseline.md](./low-load-baseline.md)
  - Main written low-load baseline used for later comparisons.
- [medium-load-results.md](./medium-load-results.md)
  - Medium-load findings and the first bottleneck diagnosis.
- [high-load-results.md](./high-load-results.md)
  - Constant high-load results between medium and peak.
- [peak-load-results.md](./peak-load-results.md)
  - Peak-load failure summary and bottleneck interpretation.
- [ramp-load-results.md](./ramp-load-results.md)
  - Threshold-style run showing where failures begin as rate increases.
- [burst-load-results.md](./burst-load-results.md)
  - Burst-style run showing spike behavior and delayed recovery.

## How to use this folder

- Start with [low-load-baseline.md](./low-load-baseline.md) for the stable reference point.
- Use [medium-load-results.md](./medium-load-results.md) to see where the main bottleneck first became visible.
- Use [high-load-results.md](./high-load-results.md), [ramp-load-results.md](./ramp-load-results.md), and [burst-load-results.md](./burst-load-results.md) to understand the system near its limit.
- Use [peak-load-results.md](./peak-load-results.md) for the full overload case.
