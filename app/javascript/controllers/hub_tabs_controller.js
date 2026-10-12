import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = { active: String }

  connect() {
    const initial = this.activeValue || this.tabTargets[0]?.dataset.tab
    this.show(initial)
  }

  select(event) {
    event.preventDefault()
    this.show(event.currentTarget.dataset.tab)
  }

  show(name) {
    for (const tab of this.tabTargets) {
      tab.classList.toggle("tab-active", tab.dataset.tab === name)
    }
    for (const panel of this.panelTargets) {
      panel.classList.toggle("hidden", panel.dataset.tab !== name)
    }
  }
}
