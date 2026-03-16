-- Create bookings table for RDS PostgreSQL
CREATE TABLE IF NOT EXISTS bookings (
  id SERIAL PRIMARY KEY,
  booking_id VARCHAR(255) UNIQUE NOT NULL,
  reservation_id VARCHAR(255) NOT NULL DEFAULT 'PENDING',
  payment_id VARCHAR(255) NOT NULL DEFAULT 'PENDING',
  ticket_id VARCHAR(255) NOT NULL DEFAULT 'PENDING',
  timestamp TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_booking_id ON bookings(booking_id);
CREATE INDEX IF NOT EXISTS idx_timestamp ON bookings(timestamp);
