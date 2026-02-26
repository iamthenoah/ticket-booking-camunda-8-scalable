package io.berndruecker.ticketbooking.adapter;

import io.berndruecker.ticketbooking.ProcessConstants;
import io.camunda.zeebe.client.api.response.ActivatedJob;
import io.camunda.zeebe.spring.client.annotation.JobWorker;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import java.io.IOException;
import java.util.Collections;
import java.util.Map;

@Component
public class GenerateTicketAdapter {

  Logger logger = LoggerFactory.getLogger(GenerateTicketAdapter.class);

  @Value("${ticketbooking.payment.endpoint:http://ticket-generator:3000/ticket}")
  private String endpoint;

  @Autowired
  private RestTemplate restTemplate;

  @JobWorker(type = "generate-ticket")
  public Map<String, Object> callGenerateTicketRestService(final ActivatedJob job) throws IOException {
    logger.info("Generate ticket via REST [" + job + "]");

    if ("ticket".equalsIgnoreCase((String)job.getVariablesAsMap().get(ProcessConstants.VAR_SIMULATE_BOOKING_FAILURE))) {

      // Simulate a network problem to the HTTP server
      throw new IOException("[Simulated] Could not connect to HTTP server");
      
    } else {
      
      // Call REST API, simply returns a ticketId
      CreateTicketResponse ticket = restTemplate.getForObject(endpoint, CreateTicketResponse.class);  
      logger.info("Succeeded with " + ticket);

      return Collections.singletonMap(ProcessConstants.VAR_TICKET_ID, ticket.ticketId);
    }
  }

  public static class CreateTicketResponse {
    public String ticketId;
  }
}
