import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "content", "info"]

  switch(event) {
    const tab = event.currentTarget.dataset.tab

    // Update tab buttons
    this.tabTargets.forEach(btn => {
      btn.classList.remove("border-indigo-500", "text-indigo-600")
      btn.classList.add("border-transparent", "text-gray-500")
    })

    event.currentTarget.classList.remove("border-transparent", "text-gray-500")
    event.currentTarget.classList.add("border-indigo-500", "text-indigo-600")

    // Update content panels
    this.contentTargets.forEach(content => {
      content.classList.add("hidden")
    })

    const activeContent = this.contentTargets.find(c => c.dataset.tab === tab)
    if (activeContent) {
      activeContent.classList.remove("hidden")
    }

    // Update info sections
    this.infoTargets.forEach(info => {
      info.classList.add("hidden")
    })

    const activeInfo = this.infoTargets.find(i => i.dataset.tab === tab)
    if (activeInfo) {
      activeInfo.classList.remove("hidden")
    }
  }
}
