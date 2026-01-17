import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source"]
  static values = { successMessage: { type: String, default: "Copied!" } }

  copy(event) {
    event.preventDefault()
    const text = this.sourceTarget.textContent.trim()

    navigator.clipboard.writeText(text).then(() => {
      this.showFeedback()
    })
  }

  showFeedback() {
    const originalText = this.sourceTarget.textContent
    this.sourceTarget.textContent = this.successMessageValue
    this.sourceTarget.classList.add("text-green-600")

    setTimeout(() => {
      this.sourceTarget.textContent = originalText
      this.sourceTarget.classList.remove("text-green-600")
    }, 1500)
  }
}
