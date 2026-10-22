import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["template", "content"]

  connect() {
    this.toggle()
  }

  toggle() {
    if (!this.hasTemplateTarget || !this.hasContentTarget) return

    if (this.element.open) {
      if (!this.contentTarget.hasChildNodes()) {
        this.contentTarget.replaceChildren(
          this.templateTarget.content.cloneNode(true),
        )
      }
    } else {
      this.contentTarget.replaceChildren()
    }
  }
}
