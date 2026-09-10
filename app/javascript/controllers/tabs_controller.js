import { Controller } from "@hotwired/stimulus"

// Tabs are styled from aria-selected (see .tf-tabs in tariffik_workspace.css)
export default class extends Controller {
  static targets = ["tab", "content", "info"]
  static values = { initial: { type: String, default: "url" } }

  connect() {
    const initialTab = this.tabTargets.find(tab => tab.dataset.tab === this.initialValue)
    if (initialTab) this.switch({ currentTarget: initialTab })
  }

  switch(event) {
    const tab = event.currentTarget.dataset.tab

    this.tabTargets.forEach(btn => {
      btn.setAttribute("aria-selected", btn === event.currentTarget ? "true" : "false")
    })

    this.contentTargets.forEach(content => {
      content.classList.toggle("hidden", content.dataset.tab !== tab)
    })

    this.infoTargets.forEach(info => {
      info.classList.toggle("hidden", info.dataset.tab !== tab)
    })
  }
}
