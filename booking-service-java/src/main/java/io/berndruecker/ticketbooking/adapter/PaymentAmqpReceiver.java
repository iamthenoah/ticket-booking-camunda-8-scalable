package io.berndruecker.ticketbooking.adapter;

import java.util.Collections;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonMappingException;
import com.fasterxml.jackson.databind.ObjectMapper;

import io.berndruecker.ticketbooking.observability.TicketBookingMetrics;
import io.camunda.zeebe.client.ZeebeClient;

@Component
public class PaymentAmqpReceiver {
  
  private final Logger logger = LoggerFactory.getLogger(PaymentAmqpReceiver.class);

  @Autowired
  private ZeebeClient client;
  
  @Autowired
  private ObjectMapper objectMapper;

  @Autowired
  private TicketBookingMetrics metrics;
  
  @RabbitListener(queues = "paymentResponse")
  @Transactional  
  public void messageReceived(String paymentResponseString) throws JsonMappingException, JsonProcessingException {
    PaymentResponseMessage paymentResponse = objectMapper.readValue(paymentResponseString, PaymentResponseMessage.class);
    logger.info("Received " + paymentResponse);

    if (paymentResponse.requestSentAtEpochMs > 0) {
      long waitMillis = Math.max(0, System.currentTimeMillis() - paymentResponse.requestSentAtEpochMs);
      metrics.recordStepDuration("payment_wait", "success", java.time.Duration.ofMillis(waitMillis));
    }

    TicketBookingMetrics.Observation stepObservation = metrics.startStep("payment_correlate");
    try {
      client.newPublishMessageCommand() //
        .messageName("msg-payment-received") //
        .correlationKey(paymentResponse.paymentRequestId) //
        .variables(Collections.singletonMap("paymentConfirmationId", paymentResponse.paymentConfirmationId)) //
        .send().join();
      stepObservation.stop("success");
    } catch (RuntimeException ex) {
      stepObservation.stop("error");
      throw ex;
    }
  }
  
  public static class PaymentResponseMessage {
    public String paymentRequestId;
    public String paymentConfirmationId;
    public long requestSentAtEpochMs;
    public String toString() {
      return "PaymentResponseMessage [paymentRequestId=" + paymentRequestId + ", paymentConfirmationId=" + paymentConfirmationId
          + ", requestSentAtEpochMs=" + requestSentAtEpochMs + "]";
    }
  }

}
