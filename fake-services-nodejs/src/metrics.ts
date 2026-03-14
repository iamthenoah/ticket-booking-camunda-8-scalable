import { Gauge, Histogram, Registry } from 'prom-client'

const LATENCY_BUCKETS = [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 30]

const register = new Registry()

const fakeStepSeconds = new Histogram({
  name: 'ticket_booking_fake_step_seconds',
  help: 'Latency for fake service workflow steps',
  labelNames: ['step', 'status'],
  buckets: LATENCY_BUCKETS,
  registers: [register]
})

const fakeStepInFlight = new Gauge({
  name: 'ticket_booking_fake_step_in_flight',
  help: 'In-flight operations for fake service workflow steps',
  labelNames: ['step'],
  registers: [register]
})

export class StepObservation {
  private readonly start = process.hrtime.bigint()
  private stopped = false

  constructor(private readonly step: string) {
    fakeStepInFlight.labels(step).inc()
  }

  stop(status: 'success' | 'error') {
    if (this.stopped) {
      return
    }

    this.stopped = true
    fakeStepInFlight.labels(this.step).dec()

    const elapsedSeconds = Number(process.hrtime.bigint() - this.start) / 1_000_000_000
    fakeStepSeconds.labels(this.step, status).observe(elapsedSeconds)
  }
}

export function startStep(step: string) {
  return new StepObservation(step)
}

export function metricsContentType() {
  return register.contentType
}

export async function renderMetrics() {
  return register.metrics()
}
