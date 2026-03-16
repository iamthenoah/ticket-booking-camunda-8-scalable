package io.berndruecker.ticketbooking.adapter;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;

@Service
@ConditionalOnProperty(name = "aws.enabled", havingValue = "true")
public class AwsStorageService {

  private final Logger logger = LoggerFactory.getLogger(AwsStorageService.class);

  @Autowired
  private JdbcTemplate jdbcTemplate;

  public void saveBooking(String bookingId, String reservationId, String paymentId, String ticketId) {
    try {
      String sql = "INSERT INTO bookings (booking_id, reservation_id, payment_id, ticket_id, timestamp) " +
                   "VALUES (?, ?, ?, ?, ?) " +
                   "ON CONFLICT (booking_id) DO NOTHING";
      
      jdbcTemplate.update(sql, bookingId, 
          reservationId != null ? reservationId : "PENDING",
          paymentId != null ? paymentId : "PENDING",
          ticketId != null ? ticketId : "PENDING",
          LocalDateTime.now());
      
      logger.info("Saved booking {} to RDS", bookingId);
    } catch (Exception e) {
      logger.error("Failed to save booking to RDS: {}", e.getMessage());
    }
  }
}

