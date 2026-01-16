import { Controller } from "@hotwired/stimulus"

// Manages free lookup limits for unauthenticated users
// Stores count in localStorage with 72-hour expiration
export default class extends Controller {
  static targets = ["form", "limitReached", "remaining"]
  static values = {
    limit: { type: Number, default: 3 },
    expiryHours: { type: Number, default: 72 },
    authenticated: { type: Boolean, default: false }
  }

  static STORAGE_KEY = "commodity_lookups"

  connect() {
    // Skip limit checking for authenticated users
    if (this.authenticatedValue) return

    this.checkAndUpdateUI()
  }

  submit(event) {
    // Skip limit checking for authenticated users
    if (this.authenticatedValue) return

    const data = this.getLookupData()

    if (data.count >= this.limitValue) {
      event.preventDefault()
      this.showLimitReached()
      return
    }

    // Increment count after successful submission
    this.incrementCount()
  }

  getLookupData() {
    const stored = localStorage.getItem(this.constructor.STORAGE_KEY)

    if (!stored) {
      return { count: 0, expiresAt: null }
    }

    try {
      const data = JSON.parse(stored)

      // Check if expired
      if (data.expiresAt && new Date(data.expiresAt) < new Date()) {
        localStorage.removeItem(this.constructor.STORAGE_KEY)
        return { count: 0, expiresAt: null }
      }

      return data
    } catch {
      localStorage.removeItem(this.constructor.STORAGE_KEY)
      return { count: 0, expiresAt: null }
    }
  }

  incrementCount() {
    const data = this.getLookupData()
    const now = new Date()

    // Set expiry if this is the first lookup
    const expiresAt = data.expiresAt || new Date(now.getTime() + this.expiryHoursValue * 60 * 60 * 1000).toISOString()

    const newData = {
      count: data.count + 1,
      expiresAt: expiresAt
    }

    localStorage.setItem(this.constructor.STORAGE_KEY, JSON.stringify(newData))
    this.checkAndUpdateUI()
  }

  checkAndUpdateUI() {
    const data = this.getLookupData()
    const remaining = Math.max(0, this.limitValue - data.count)

    // Update remaining count display
    if (this.hasRemainingTarget) {
      this.remainingTarget.textContent = remaining
      this.remainingTarget.closest('[data-remaining-wrapper]')?.classList.toggle('hidden', remaining === 0)
    }

    // Show/hide form vs limit reached
    if (data.count >= this.limitValue) {
      this.showLimitReached()
    }
  }

  showLimitReached() {
    if (this.hasFormTarget) {
      this.formTarget.classList.add('hidden')
    }
    if (this.hasLimitReachedTarget) {
      this.limitReachedTarget.classList.remove('hidden')
    }
  }

  // For testing/debugging - reset the counter
  reset() {
    localStorage.removeItem(this.constructor.STORAGE_KEY)
    this.checkAndUpdateUI()
    if (this.hasFormTarget) {
      this.formTarget.classList.remove('hidden')
    }
    if (this.hasLimitReachedTarget) {
      this.limitReachedTarget.classList.add('hidden')
    }
  }
}
