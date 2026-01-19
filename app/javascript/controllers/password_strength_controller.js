import { Controller } from "@hotwired/stimulus"

// Password strength validation controller for real-time feedback
// Used on registration, password reset, and account settings forms
export default class extends Controller {
  static targets = [
    "input",
    "length", "lengthIcon",
    "uppercase", "uppercaseIcon",
    "lowercase", "lowercaseIcon",
    "digit", "digitIcon"
  ]

  validate() {
    const password = this.inputTarget.value

    this.updateRequirement(
      this.lengthTarget,
      this.lengthIconTarget,
      password.length >= 8
    )

    this.updateRequirement(
      this.uppercaseTarget,
      this.uppercaseIconTarget,
      /[A-Z]/.test(password)
    )

    this.updateRequirement(
      this.lowercaseTarget,
      this.lowercaseIconTarget,
      /[a-z]/.test(password)
    )

    this.updateRequirement(
      this.digitTarget,
      this.digitIconTarget,
      /\d/.test(password)
    )
  }

  updateRequirement(element, icon, isMet) {
    if (isMet) {
      icon.innerHTML = "✓"
      icon.classList.remove("text-gray-400")
      icon.classList.add("text-brand-mint")
      element.classList.remove("text-gray-600")
      element.classList.add("text-brand-dark")
    } else {
      icon.innerHTML = "○"
      icon.classList.add("text-gray-400")
      icon.classList.remove("text-brand-mint")
      element.classList.add("text-gray-600")
      element.classList.remove("text-brand-dark")
    }
  }
}
