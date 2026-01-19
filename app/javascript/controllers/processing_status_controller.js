import { Controller } from "@hotwired/stimulus"

// Shows progressive status messages while processing a product lookup
// Used on the show page when lookup is in pending state
export default class extends Controller {
  static targets = ["message", "submessage"]
  static values = {
    photo: { type: Boolean, default: false }
  }

  // Progress messages for URL-based lookups
  static urlMessages = [
    { delay: 0, message: "Fetching product page...", submessage: "This may take a few seconds" },
    { delay: 4000, message: "Analyzing page content...", submessage: "Extracting product details" },
    { delay: 8000, message: "Trying enhanced fetch methods...", submessage: "Some sites need extra effort" },
    { delay: 14000, message: "Using advanced techniques...", submessage: "Almost there" },
    { delay: 20000, message: "Still working...", submessage: "The site has strong protection" },
    { delay: 30000, message: "Please wait...", submessage: "This is taking longer than usual" }
  ]

  // Progress messages for photo lookups
  static photoMessages = [
    { delay: 0, message: "Analyzing product image...", submessage: "This may take a few seconds" },
    { delay: 4000, message: "Identifying product details...", submessage: "Processing image content" },
    { delay: 8000, message: "Researching product information...", submessage: "Finding matching products" },
    { delay: 14000, message: "Determining commodity code...", submessage: "Almost there" }
  ]

  connect() {
    this.timers = []
    this.startProgress()
  }

  disconnect() {
    this.clearTimers()
  }

  startProgress() {
    const messages = this.photoValue
      ? this.constructor.photoMessages
      : this.constructor.urlMessages

    messages.forEach(({ delay, message, submessage }) => {
      const timer = setTimeout(() => {
        this.updateMessage(message, submessage)
      }, delay)
      this.timers.push(timer)
    })
  }

  updateMessage(message, submessage) {
    if (this.hasMessageTarget) {
      this.messageTarget.textContent = message
    }
    if (this.hasSubmessageTarget) {
      this.submessageTarget.textContent = submessage
    }
  }

  clearTimers() {
    this.timers.forEach(timer => clearTimeout(timer))
    this.timers = []
  }
}
