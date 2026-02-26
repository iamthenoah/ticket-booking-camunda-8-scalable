const { v4: uuidv4 } = require('uuid')
const amqp = require('amqplib/callback_api')
const express = require('express')

////////////////////////////////////
// FAKE SEAT RESERVATION SERVICE
////////////////////////////////////
import { ZBClient } from 'zeebe-node'
require('dotenv').config()

const port = Number(process.env.PORT || 3000)
const rabbitMqUrl = process.env.RABBITMQ_URL || 'amqp://guest:guest@rabbitmq:5672'

let rabbitConnection: any = null
let rabbitChannel: any = null
let isShuttingDown = false

const zeebeClient = new ZBClient()
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
const queuePaymentRequest = 'paymentRequest'
const queuePaymentResponse = 'paymentResponse'

amqp.connect(rabbitMqUrl, function (error0, connection) {
  if (error0) {
    throw error0
  }
  rabbitConnection = connection

  connection.createChannel(function (error1, channel) {
    if (error1) {
      throw error1
    }
    rabbitChannel = channel

    channel.assertQueue(queuePaymentRequest, { durable: true })
    channel.assertQueue(queuePaymentResponse, { durable: true })

    channel.consume(
      queuePaymentRequest,
      function (inputMessage) {
        var paymentRequestId = inputMessage.content.toString()
        var paymentConfirmationId = uuidv4()

        console.log('\n\n [x] Received payment request %s', paymentRequestId)

        var outputMessage =
          '{"paymentRequestId": "' + paymentRequestId + '", "paymentConfirmationId": "' + paymentConfirmationId + '"}'

        channel.sendToQueue(queuePaymentResponse, Buffer.from(outputMessage))
        console.log(' [x] Sent payment response %s', outputMessage)
      },
      {
        noAck: true
      }
    )
  })
})

////////////////////////////////////
// FAKE TICKET GENERATION SERVICE
////////////////////////////////////
var app = express()

app.get('/health', (req, res) => {
  // Lightweight health endpoint for Kubernetes probes.
  res.status(200).json({ status: 'ok' })
})

const server = app.listen(port, () => {
  console.log(`HTTP Server running on port ${port}`)
})

app.get('/ticket', (req, res, next) => {
  var ticketId = uuidv4()
  console.log('\n\n [x] Create Ticket %s', ticketId)
  res.json({ ticketId: ticketId })
})

async function shutdown(signal: string) {
  if (isShuttingDown) {
    return
  }
  isShuttingDown = true

  console.log(`${signal} received. Closing worker and network connections...`)

  // Stop accepting new HTTP traffic first.
  server.close(() => {
    console.log('HTTP server closed')
  })

  try {
    await worker.close()
  } catch (error) {
    console.error('Failed to close Zeebe worker cleanly', error)
  }

  try {
    await zeebeClient.close()
  } catch (error) {
    console.error('Failed to close Zeebe client cleanly', error)
  }

  try {
    if (rabbitChannel) {
      rabbitChannel.close()
    }
    if (rabbitConnection) {
      rabbitConnection.close()
    }
  } catch (error) {
    console.error('Failed to close RabbitMQ connection cleanly', error)
  }

  setTimeout(() => {
    process.exit(0)
  }, 1000)
}

process.on('SIGTERM', () => {
  void shutdown('SIGTERM')
})

process.on('SIGINT', () => {
  void shutdown('SIGINT')
})
