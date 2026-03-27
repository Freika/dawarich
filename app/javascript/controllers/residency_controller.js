import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "frame", "yearSelect", "overlay"]

  static values = {
    url: String,
  }

  connect() {
    this._boundOpen = () => this.open()
    this._boundLoaded = () => this._hideLoading()
    document.addEventListener("residency:open", this._boundOpen)
    this.frameTarget.addEventListener("turbo:frame-load", this._boundLoaded)
  }

  disconnect() {
    document.removeEventListener("residency:open", this._boundOpen)
    this.frameTarget.removeEventListener("turbo:frame-load", this._boundLoaded)
  }

  open() {
    this.modalTarget.classList.add("modal-open")

    if (!this._loaded) {
      this.frameTarget.src = this.urlValue
      this._loaded = true
    }
  }

  close() {
    this.modalTarget.classList.remove("modal-open")
  }

  changeYear() {
    this._showLoading()
    const year = this.yearSelectTarget.value
    this.frameTarget.src = `${this.urlValue}?year=${year}`
  }

  _showLoading() {
    this.overlayTarget.classList.remove("hidden")
    this.overlayTarget.classList.add("flex")
  }

  _hideLoading() {
    this.overlayTarget.classList.add("hidden")
    this.overlayTarget.classList.remove("flex")
  }
}
