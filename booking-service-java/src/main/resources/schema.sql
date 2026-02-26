CREATE TABLE IF NOT EXISTS ticket_bookings (
  booking_reference_id VARCHAR(64) PRIMARY KEY,
  reservation_id VARCHAR(64),
  payment_confirmation_id VARCHAR(64),
  ticket_id VARCHAR(64),
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
