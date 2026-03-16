package io.berndruecker.ticketbooking.adapter;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;

@Service
@ConditionalOnProperty(name = "aws.enabled", havingValue = "true")
public class AwsStorageService {

  private final Logger logger = LoggerFactory.getLogger(AwsStorageService.class);
  private final DynamoDbClient dynamoDb = DynamoDbClient.builder().build();
  private final String tableName = System.getenv().getOrDefault("AWS_DYNAMODB_TABLE", "bookings");

  public void saveBooking(String bookingId, String reservationId, String paymentId, String ticketId) {
    try {
      Map<String, AttributeValue> item = new HashMap<>();
      item.put("bookingId", AttributeValue.builder().s(bookingId).build());
      item.put("reservationId", AttributeValue.builder().s(reservationId != null ? reservationId : "PENDING").build());
      item.put("paymentId", AttributeValue.builder().s(paymentId != null ? paymentId : "PENDING").build());
      item.put("ticketId", AttributeValue.builder().s(ticketId != null ? ticketId : "PENDING").build());
      item.put("timestamp", AttributeValue.builder().s(LocalDateTime.now().toString()).build());

      dynamoDb.putItem(PutItemRequest.builder().tableName(tableName).item(item).build());
      logger.info("Saved booking {} to AWS", bookingId);
    } catch (Exception e) {
      logger.error("Failed to save booking to AWS: {}", e.getMessage());
    }
  }
}
