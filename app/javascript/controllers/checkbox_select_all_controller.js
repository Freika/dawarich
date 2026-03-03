import BaseController from "./base_controller"

// Connects to data-controller="checkbox-select-all"
export default class extends BaseController {
  static targets = ["parent", "child", "deleteButton"]

  connect() {
    this.parentTarget.checked = false
    this.childTargets.forEach((x) => {
      x.checked = false
    })
    this.updateDeleteButtonVisibility()
  }

  toggleChildren() {
    if (this.parentTarget.checked) {
      this.childTargets.forEach((x) => {
        x.checked = true
      })
    } else {
      this.childTargets.forEach((x) => {
        x.checked = false
      })
    }
    this.updateDeleteButtonVisibility()
  }

  toggleParent() {
    if (this.childTargets.map((x) => x.checked).includes(false)) {
      this.parentTarget.checked = false
    } else {
      this.parentTarget.checked = true
    }
    this.updateDeleteButtonVisibility()
  }

  updateDeleteButtonVisibility() {
    const hasCheckedItems = this.childTargets.some((target) => target.checked)

    if (this.hasDeleteButtonTarget) {
      this.deleteButtonTarget.style.display = hasCheckedItems
        ? "inline-block"
        : "none"
    }
  }
}
