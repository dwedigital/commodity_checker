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
      icon.innerHTML = "&#10003;" // checkmark
      icon.classList.remove("text-gray-400")
      icon.classList.add("text-green-500")
      element.classList.remove("text-gray-500")
      element.classList.add("text-green-600")
    } else {
      icon.innerHTML = "&#9675;" // circle
      icon.classList.add("text-gray-400")
      icon.classList.remove("text-green-500")
      element.classList.add("text-gray-500")
      element.classList.remove("text-green-600")
    }
  }
}
