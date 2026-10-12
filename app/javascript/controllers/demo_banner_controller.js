import { Controller } from "@hotwired/stimulus"
import { translate } from "i18n"

export default class extends Controller {
  static targets = ["deleteButton", "loadingState", "label"]

  dismiss() {
    this.element.remove()
  }

  confirmDelete(event) {
    const ok = window.confirm(translate("demo.confirm_delete"))
    if (!ok) {
      event.preventDefault()
      return
    }

    this.showLoading()
  }

  showLoading() {
    if (this.hasLoadingStateTarget) {
      this.loadingStateTarget.classList.remove("hidden")
    }
    if (this.hasDeleteButtonTarget) {
      this.deleteButtonTarget.disabled = true
      this.deleteButtonTarget.classList.add("opacity-50", "pointer-events-none")
    }
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = translate("demo.removing_data")
    }
  }
}
