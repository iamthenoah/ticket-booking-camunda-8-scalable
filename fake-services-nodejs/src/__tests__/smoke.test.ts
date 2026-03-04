describe('Fake Services Health Check', () => {
  test('should have dependencies installed', () => {
    // Basic smoke test - verifies dependencies are available
    expect(require('express')).toBeDefined()
    expect(require('amqplib')).toBeDefined()
    expect(require('zeebe-node')).toBeDefined()
  })

  test('should be able to load environment', () => {
    // Verify dotenv dependency is available
    expect(require('dotenv')).toBeDefined()
  })
})
