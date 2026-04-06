import { createConsumer } from "@rails/actioncable"

let sharedConsumer = null

export function getSharedConsumer() {
  if (!sharedConsumer) {
    sharedConsumer = createConsumer()
  }
  return sharedConsumer
}
