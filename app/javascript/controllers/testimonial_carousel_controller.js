import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["slide", "dot"]
  static values = { index: { type: Number, default: 0 } }

  connect() {
    this.showSlide(this.indexValue)
    this.startAutoplay()
  }

  disconnect() {
    this.stopAutoplay()
  }

  next() {
    const nextIndex = (this.indexValue + 1) % this.slideTargets.length
    this.indexValue = nextIndex
  }

  previous() {
    const prevIndex = (this.indexValue - 1 + this.slideTargets.length) % this.slideTargets.length
    this.indexValue = prevIndex
  }

  goToSlide(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    this.indexValue = index
  }

  indexValueChanged() {
    this.showSlide(this.indexValue)
    this.updateDots()
  }

  showSlide(index) {
    this.slideTargets.forEach((slide, i) => {
      slide.classList.toggle("hidden", i !== index)
    })
  }

  updateDots() {
    this.dotTargets.forEach((dot, i) => {
      if (i === this.indexValue) {
        dot.classList.add("bg-brand-dark")
        dot.classList.remove("bg-gray-300")
      } else {
        dot.classList.remove("bg-brand-dark")
        dot.classList.add("bg-gray-300")
      }
    })
  }

  startAutoplay() {
    this.autoplayInterval = setInterval(() => {
      this.next()
    }, 5000)
  }

  stopAutoplay() {
    if (this.autoplayInterval) {
      clearInterval(this.autoplayInterval)
    }
  }

  pauseAutoplay() {
    this.stopAutoplay()
  }

  resumeAutoplay() {
    this.startAutoplay()
  }
}
