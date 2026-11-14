import { Controller } from "@hotwired/stimulus"

// Turns a server-rendered element into a document event: a turbo stream
// renders the element, and its arrival tells the page what happened.
export default class extends Controller {
  static values = { name: String }

  connect() {
    document.dispatchEvent(new CustomEvent(this.nameValue))
    this.element.remove()
  }
}
