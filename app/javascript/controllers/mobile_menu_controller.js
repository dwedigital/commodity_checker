import { Controller } from "@hotwired/stimulus"

// Mobile menu toggle controller
export default class extends Controller {
  static targets = ["menu", "openIcon", "closeIcon"]

  connect() {
    this.isToggling = false
  }

  toggle(event) {
    // Prevent double-firing on touch devices (touchend + click both fire)
    if (this.isToggling) return
    this.isToggling = true

    // Reset flag after a short delay
    setTimeout(() => { this.isToggling = false }, 100)

    this.menuTarget.classList.toggle("hidden")
    this.openIconTarget.classList.toggle("hidden")
    this.closeIconTarget.classList.toggle("hidden")
  }

  close() {
    this.menuTarget.classList.add("hidden")
    this.openIconTarget.classList.remove("hidden")
    this.closeIconTarget.classList.add("hidden")
  }
}
