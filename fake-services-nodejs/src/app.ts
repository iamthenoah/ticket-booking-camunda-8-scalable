const { v4: uuidv4 } = require('uuid')

////////////////////////////////////
// FAKE SEAT RESERVATION SERVICE
////////////////////////////////////
import { ZBClient } from 'zeebe-node'
require('dotenv').config()

const zeebeClient = new ZBClient({
  hostname: process.env.ZEEBE_ADDRESS || 'localhost:26500'
})
const worker = zeebeClient.createWorker('reserve-seats', reserveSeatsHandler)

function reserveSeatsHandler(job, _, worker) {
  console.log('\n\n Reserve seats now...')
  console.log(job)

  // Do the real reservation
  // TODO: Fake some results! Fake an error (when exactly?)
  if ('seats' !== job.variables.simulateBookingFailure) {
    console.log('Successul :-)')
    return job.complete({
      reservationId: '1234'
    })
  } else {
    console.log('ERROR: Seats could not be reserved!')
    return job.error('ErrorSeatsNotAvailable')
  }
}

////////////////////////////////////
// FAKE PAYMENT SERVICE
////////////////////////////////////
var amqp = require('amqplib/callback_api')

const queuePaymentRequest = 'paymentRequest'
const queuePaymentResponse = 'paymentResponse'
const amqpUrl = process.env.AMQP_URL || 'amqp://guest:guest@rabbitmq:5672'

console.log('Connecting to AMQP at:', amqpUrl.replace(/:[^:@]*@/, ':****@'))

amqp.connect(amqpUrl, function (error0, connection) {
  if (error0) {
    console.error('ERROR connecting to AMQP:', error0)
    throw error0
  }
  console.log('✓ Connected to AMQP')

  connection.createChannel(function (error1, channel) {
    if (error1) {
      console.error('ERROR creating channel:', error1)
      throw error1
    }
    console.log('✓ Channel created')

    channel.assertQueue(queuePaymentRequest, { durable: true })
    console.log('✓ Queue created/verified:', queuePaymentRequest)

    channel.assertQueue(queuePaymentResponse, { durable: true })
    console.log('✓ Queue created/verified:', queuePaymentResponse)

    console.log('✓ Starting payment request consumer...')
    channel.consume(
      queuePaymentRequest,
      function (inputMessage) {
        if (inputMessage) {
          var paymentRequestId = inputMessage.content.toString()
          var paymentConfirmationId = uuidv4()

          console.log('\n✓ [PAYMENT] Received payment request: %s', paymentRequestId)

          var outputMessage =
            '{"paymentRequestId": "' + paymentRequestId + '", "paymentConfirmationId": "' + paymentConfirmationId + '"}'

          channel.sendToQueue(queuePaymentResponse, Buffer.from(outputMessage))
          console.log('✓ [PAYMENT] Sent payment response: %s', outputMessage)
          channel.ack(inputMessage)
        }
      },
      {
        noAck: false
      }
    )
  })
})

////////////////////////////////////
// FAKE TICKET GENERATION SERVICE
////////////////////////////////////
var express = require('express')
var app = express()

app.listen(3000, () => {
  console.log('HTTP Server running on port 3000')
})

app.get('/ticket', (req, res, next) => {
  var ticketId = uuidv4()
  console.log('\n\n [x] Create Ticket %s', ticketId)
  res.json({ ticketId: ticketId })
})
