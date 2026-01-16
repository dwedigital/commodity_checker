import { Controller } from "@hotwired/stimulus"

// Manages the UI for lookup limits (display only - tracking is server-side)
export default class extends Controller {
  static targets = ["form", "limitReached", "remaining", "lookupText"]
  static values = {
    remaining: { type: Number, default: 3 },
    authenticated: { type: Boolean, default: false },
    limitReached: { type: Boolean, default: false }
  }

  connect() {
    // Skip for authenticated users
    if (this.authenticatedValue) return

    this.updateUI()
  }

  // Called when remaining value changes (e.g., after Turbo updates)
  remainingValueChanged() {
    if (this.authenticatedValue) return
    this.updateUI()
  }

  // Called when limitReached value changes
  limitReachedValueChanged() {
    if (this.authenticatedValue) return
    this.updateUI()
  }

  updateUI() {
    const remaining = this.remainingValue

    // Update remaining count display
    if (this.hasRemainingTarget) {
      this.remainingTarget.textContent = remaining
      this.remainingTarget.closest('[data-remaining-wrapper]')?.classList.toggle('hidden', remaining === 0)
    }

    // Update singular/plural text
    if (this.hasLookupTextTarget) {
      this.lookupTextTarget.textContent = remaining === 1 ? 'lookup' : 'lookups'
    }

    // Show/hide form vs limit reached based on server state
    if (this.limitReachedValue || remaining <= 0) {
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
}
