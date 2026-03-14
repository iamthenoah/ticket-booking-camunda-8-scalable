package io.berndruecker.ticketbooking.adapter;

import io.berndruecker.ticketbooking.ProcessConstants;
import io.berndruecker.ticketbooking.observability.TicketBookingMetrics;
import io.camunda.zeebe.client.api.response.ActivatedJob;
import io.camunda.zeebe.spring.client.annotation.JobWorker;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import java.util.Collections;
import java.util.Map;
import java.util.UUID;

@Component
public class RetrievePaymentAdapter {
  
  private final Logger logger = LoggerFactory.getLogger(RetrievePaymentAdapter.class);
  
  public static String RABBIT_QUEUE_NAME = "paymentRequest";
  
  @Autowired
  protected RabbitTemplate rabbitTemplate;

  @Autowired
  private ObjectMapper objectMapper;

  @Autowired
  private TicketBookingMetrics metrics;
  
  @JobWorker(type = "retrieve-payment")
  public Map<String, Object> retrievePayment(final ActivatedJob job) {
      TicketBookingMetrics.Observation stepObservation = metrics.startStep("payment_publish");
      logger.info("Send message to retrieve payment [" + job + "]");
      try {
          String paymentRequestId = UUID.randomUUID().toString();
          long requestSentAtEpochMs = System.currentTimeMillis();
          String paymentRequest = objectMapper.writeValueAsString(
              new PaymentRequestMessage(paymentRequestId, requestSentAtEpochMs));

          rabbitTemplate.convertAndSend(RABBIT_QUEUE_NAME, paymentRequest);
          stepObservation.stop("success");

          return Collections.singletonMap(ProcessConstants.VAR_PAYMENT_REQUEST_ID, paymentRequestId);
      } catch (JsonProcessingException ex) {
          stepObservation.stop("error");
          throw new IllegalStateException("Could not serialize payment request payload.", ex);
      } catch (RuntimeException ex) {
          stepObservation.stop("error");
          throw ex;
      }
  }

  public static class PaymentRequestMessage {
    public String paymentRequestId;
    public long requestSentAtEpochMs;

    public PaymentRequestMessage(String paymentRequestId, long requestSentAtEpochMs) {
      this.paymentRequestId = paymentRequestId;
      this.requestSentAtEpochMs = requestSentAtEpochMs;
    }
  }
}
