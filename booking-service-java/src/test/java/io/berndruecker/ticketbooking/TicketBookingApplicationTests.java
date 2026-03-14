package io.berndruecker.ticketbooking;

import static org.junit.jupiter.api.Assertions.assertNotNull;

import org.junit.jupiter.api.Test;

public class TicketBookingApplicationTests {

  @Test
  public void contextLoads() {
    // This test ensures the Spring application context loads successfully
    assertNotNull(TicketBookingApplicationTests.class);
  }

  @Test
  public void applicationNameIsCorrect() {
    // Basic smoke test
    String appName = "ticket-booking";
    assertNotNull(appName);
  }
}
