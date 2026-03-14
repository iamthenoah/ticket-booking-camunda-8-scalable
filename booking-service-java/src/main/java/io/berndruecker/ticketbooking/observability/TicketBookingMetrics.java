package io.berndruecker.ticketbooking.observability;

import java.time.Duration;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.atomic.AtomicInteger;

import org.springframework.stereotype.Component;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Tags;
import io.micrometer.core.instrument.Timer;

@Component
public class TicketBookingMetrics {

  private static final Duration[] LATENCY_SLOS = new Duration[] {
      Duration.ofMillis(50),
      Duration.ofMillis(100),
      Duration.ofMillis(250),
      Duration.ofMillis(500),
      Duration.ofSeconds(1),
      Duration.ofSeconds(2),
      Duration.ofSeconds(5),
      Duration.ofSeconds(10),
      Duration.ofSeconds(30),
      Duration.ofSeconds(60)
  };

  private final MeterRegistry registry;
  private final AtomicInteger requestsInFlight = new AtomicInteger();
  private final ConcurrentMap<String, AtomicInteger> stepInFlight = new ConcurrentHashMap<>();

  public TicketBookingMetrics(MeterRegistry registry) {
    this.registry = registry;
    registry.gauge("ticket.booking.requests.in.flight", requestsInFlight);
  }

  public Observation startRequest() {
    requestsInFlight.incrementAndGet();
    return new Observation(null);
  }

  public Observation startStep(String step) {
    stepGauge(step).incrementAndGet();
    return new Observation(step);
  }

  public void recordStepDuration(String step, String status, Duration duration) {
    stepTimer(step, status).record(duration);
  }

  private AtomicInteger stepGauge(String step) {
    return stepInFlight.computeIfAbsent(step, key ->
        registry.gauge("ticket.booking.step.in.flight", Tags.of("step", key), new AtomicInteger()));
  }

  private Timer requestTimer(String status) {
    return Timer.builder("ticket.booking.request")
        .description("End-to-end booking request duration")
        .publishPercentileHistogram()
        .serviceLevelObjectives(LATENCY_SLOS)
        .minimumExpectedValue(Duration.ofMillis(1))
        .maximumExpectedValue(Duration.ofSeconds(60))
        .tag("status", status)
        .register(registry);
  }

  private Timer stepTimer(String step, String status) {
    return Timer.builder("ticket.booking.step")
        .description("Booking workflow step duration")
        .publishPercentileHistogram()
        .serviceLevelObjectives(LATENCY_SLOS)
        .minimumExpectedValue(Duration.ofMillis(1))
        .maximumExpectedValue(Duration.ofSeconds(60))
        .tags("step", step, "status", status)
        .register(registry);
  }

  public final class Observation {
    private final String step;
    private final long startNanos = System.nanoTime();
    private boolean stopped;

    private Observation(String step) {
      this.step = step;
    }

    public void stop(String status) {
      if (stopped) {
        return;
      }

      Duration elapsed = Duration.ofNanos(System.nanoTime() - startNanos);
      stopped = true;

      if (step == null) {
        requestsInFlight.decrementAndGet();
        requestTimer(status).record(elapsed);
      } else {
        stepGauge(step).decrementAndGet();
        stepTimer(step, status).record(elapsed);
      }
    }
  }
}
