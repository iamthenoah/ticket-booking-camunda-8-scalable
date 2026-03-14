const { v4: uuidv4 } = require('uuid')
const amqp = require('amqplib/callback_api')
const express = require('express')

import { ZBClient } from 'zeebe-node'
import { metricsContentType, renderMetrics, startStep } from './metrics'

require('dotenv').config()

type PaymentRequestMessage = {
  paymentRequestId: string
  requestSentAtEpochMs: number
}

type PaymentResponseMessage = {
  paymentRequestId: string
  paymentConfirmationId: string
  requestSentAtEpochMs: number
}

////////////////////////////////////
// FAKE SEAT RESERVATION SERVICE
////////////////////////////////////
const zeebeClient = new ZBClient()
zeebeClient.createWorker('reserve-seats', reserveSeatsHandler)

function reserveSeatsHandler(job: any) {
  const observation = startStep('reserve_seats')
  console.log('\n\n Reserve seats now...')
  console.log(job)

  try {
    if ('seats' !== job.variables.simulateBookingFailure) {
      console.log('Successul :-)')
      return job.complete({
        reservationId: '1234'
      }).then((ack: any) => {
        observation.stop('success')
        return ack
      }).catch((error: unknown) => {
        observation.stop('error')
        throw error
      })
    }

    console.log('ERROR: Seats could not be reserved!')
    return job.error('ErrorSeatsNotAvailable').then((ack: any) => {
      observation.stop('error')
      return ack
    }).catch((error: unknown) => {
      observation.stop('error')
      throw error
    })
  } catch (error) {
    observation.stop('error')
    throw error
  }
}

////////////////////////////////////
// FAKE PAYMENT SERVICE
////////////////////////////////////
const queuePaymentRequest = 'paymentRequest'
const queuePaymentResponse = 'paymentResponse'

amqp.connect('amqp://rabbitmq', function (error0: Error | null, connection: any) {
  if (error0) {
    throw error0
  }
  connection.createChannel(function (error1: Error | null, channel: any) {
    if (error1) {
      throw error1
    }

    channel.assertQueue(queuePaymentRequest, { durable: true })
    channel.assertQueue(queuePaymentResponse, { durable: true })

    channel.consume(
      queuePaymentRequest,
      function (inputMessage: any) {
        if (!inputMessage) {
          return
        }

        const observation = startStep('payment_consume')
        try {
          const paymentRequest = JSON.parse(inputMessage.content.toString()) as PaymentRequestMessage
          const paymentConfirmationId = uuidv4()
          const outputMessage: PaymentResponseMessage = {
            paymentRequestId: paymentRequest.paymentRequestId,
            paymentConfirmationId,
            requestSentAtEpochMs: paymentRequest.requestSentAtEpochMs
          }

          console.log('\n\n [x] Received payment request %s', paymentRequest.paymentRequestId)

          channel.sendToQueue(queuePaymentResponse, Buffer.from(JSON.stringify(outputMessage)))
          console.log(' [x] Sent payment response %s', JSON.stringify(outputMessage))
          observation.stop('success')
        } catch (error) {
          observation.stop('error')
          console.error(' [x] Could not process payment request', error)
        }
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
const app = express()

app.listen(3000, () => {
  console.log('HTTP Server running on port 3000')
})

app.get('/ticket', (req: any, res: any) => {
  const observation = startStep('ticket_http')
  try {
    const ticketId = uuidv4()
    console.log('\n\n [x] Create Ticket %s', ticketId)
    res.json({ ticketId })
    observation.stop('success')
  } catch (error) {
    observation.stop('error')
    throw error
  }
})

app.get('/metrics', async (_req: any, res: any) => {
  res.set('Content-Type', metricsContentType())
  res.end(await renderMetrics())
})
