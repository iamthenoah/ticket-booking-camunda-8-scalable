package io.berndruecker.ticketbooking.repository;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class TicketBookingRepository {

  @Autowired
  private JdbcTemplate jdbcTemplate;

  public void save(String bookingReferenceId, String reservationId, String paymentConfirmationId, String ticketId) {
    // Keep persistence minimal: one row per successful booking flow.
    jdbcTemplate.update(
      "INSERT INTO ticket_bookings (booking_reference_id, reservation_id, payment_confirmation_id, ticket_id) VALUES (?, ?, ?, ?)",
      bookingReferenceId,
      reservationId,
      paymentConfirmationId,
      ticketId
    );
  }
}
