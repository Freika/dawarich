import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["v1Section", "v2Section"]

  connect() {
    this.toggle()
  }

  toggle() {
    const selected = this.element.querySelector(
      'input[name="maps[preferred_version]"]:checked',
    )
    const isV1 = selected?.value === "v1"

    this.v1SectionTarget.style.display = isV1 ? "" : "none"
    this.v2SectionTarget.style.display = isV1 ? "none" : ""
  }
}
