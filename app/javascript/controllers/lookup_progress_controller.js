import { Controller } from "@hotwired/stimulus"

// Manages progressive status messages during lookup submissions
// Shows user-friendly progress updates while waiting for server response
// Works with both Turbo Frames and regular Turbo Drive form submissions
export default class extends Controller {
  static targets = ["button", "buttonText", "spinner", "status"]
  static values = {
    urlLookup: { type: Boolean, default: false }
  }

  // Progress messages for URL-based lookups (longer process)
  static urlMessages = [
    { delay: 0, message: "Fetching product page..." },
    { delay: 3000, message: "Analyzing page content..." },
    { delay: 6000, message: "Trying enhanced fetch methods..." },
    { delay: 10000, message: "Using advanced techniques..." },
    { delay: 15000, message: "Almost there, please wait..." }
  ]

  // Progress messages for description-based lookups (faster)
  static descriptionMessages = [
    { delay: 0, message: "Analyzing description..." },
    { delay: 3000, message: "Finding best commodity code..." }
  ]

  connect() {
    this.timers = []
    this.isSubmitting = false
    this.originalButtonText = this.hasButtonTextTarget ? this.buttonTextTarget.textContent : "Get Code"

    // Listen for Turbo events to know when request completes
    this.boundHandleFrameLoad = this.handleFrameLoad.bind(this)
    this.boundHandleFrameError = this.handleFrameError.bind(this)
    this.boundHandleSubmitEnd = this.handleSubmitEnd.bind(this)
    this.boundHandleBeforeVisit = this.handleBeforeVisit.bind(this)

    // Turbo Frame events
    document.addEventListener("turbo:frame-load", this.boundHandleFrameLoad)
    document.addEventListener("turbo:frame-render", this.boundHandleFrameLoad)
    document.addEventListener("turbo:fetch-request-error", this.boundHandleFrameError)

    // Turbo Drive events (for regular form submissions)
    document.addEventListener("turbo:submit-end", this.boundHandleSubmitEnd)
    document.addEventListener("turbo:before-visit", this.boundHandleBeforeVisit)
  }

  disconnect() {
    this.clearTimers()
    document.removeEventListener("turbo:frame-load", this.boundHandleFrameLoad)
    document.removeEventListener("turbo:frame-render", this.boundHandleFrameLoad)
    document.removeEventListener("turbo:fetch-request-error", this.boundHandleFrameError)
    document.removeEventListener("turbo:submit-end", this.boundHandleSubmitEnd)
    document.removeEventListener("turbo:before-visit", this.boundHandleBeforeVisit)
  }

  // Called when form is submitted
  submit(event) {
    // Detect if this is a URL-based lookup
    const form = event.target
    const urlInput = form.querySelector('input[type="url"], input[name*="url"]')
    const hasUrl = urlInput && urlInput.value.trim().length > 0

    this.isSubmitting = true
    this.startProgress(hasUrl)
  }

  startProgress(isUrlLookup) {
    this.clearTimers()

    // Disable button and show spinner
    if (this.hasButtonTarget) {
      this.buttonTarget.disabled = true
    }
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.remove("hidden")
    }

    // Choose message set based on lookup type
    const messages = isUrlLookup
      ? this.constructor.urlMessages
      : this.constructor.descriptionMessages

    // Schedule progressive messages
    messages.forEach(({ delay, message }) => {
      const timer = setTimeout(() => {
        this.updateStatus(message)
      }, delay)
      this.timers.push(timer)
    })
  }

  updateStatus(message) {
    if (this.hasButtonTextTarget) {
      this.buttonTextTarget.textContent = message
    }
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = message
      this.statusTarget.classList.remove("hidden")
    }
  }

  handleFrameLoad(event) {
    // Check if this is our frame
    const frame = event.target
    if (frame.id === "lookup_result") {
      this.resetProgress()
    }
  }

  handleFrameError(event) {
    this.resetProgress()
  }

  // Handle Turbo Drive form submission end
  handleSubmitEnd(event) {
    if (this.isSubmitting) {
      // Form submission completed - page will redirect or re-render with errors
      // Reset progress in case we stay on the same page (validation errors)
      this.resetProgress()
    }
  }

  // Handle Turbo Drive navigation (page is about to change)
  handleBeforeVisit(event) {
    if (this.isSubmitting) {
      // Page is navigating away - clear timers but don't reset button
      // (page will be replaced anyway)
      this.clearTimers()
      this.isSubmitting = false
    }
  }

  resetProgress() {
    this.clearTimers()
    this.isSubmitting = false

    // Re-enable button
    if (this.hasButtonTarget) {
      this.buttonTarget.disabled = false
    }
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.add("hidden")
    }
    if (this.hasButtonTextTarget) {
      this.buttonTextTarget.textContent = this.originalButtonText
    }
    if (this.hasStatusTarget) {
      this.statusTarget.classList.add("hidden")
    }
  }

  clearTimers() {
    this.timers.forEach(timer => clearTimeout(timer))
    this.timers = []
  }
}
