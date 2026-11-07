import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  navigate(event) {
    window.Turbo.visit(event.target.value)
  }
}
