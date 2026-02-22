import { Controller } from "@hotwired/stimulus"
import Flash from "./flash_controller"

export default class extends Controller {
  static values = {
    text: String,
  }

  static targets = ["icon", "text"]

  copy() {
    navigator.clipboard
      .writeText(this.textValue)
      .then(() => {
        this.showButtonFeedback()
        Flash.show("notice", "Link copied to clipboard!")
      })
      .catch((err) => {
        console.error("Failed to copy text: ", err)
        Flash.show("error", "Failed to copy link")
      })
  }

  showButtonFeedback() {
    const button = this.element
    const originalClasses = button.className
    const originalHTML = button.innerHTML

    // Change button appearance
    button.className = "btn btn-success btn-xs"
    button.innerHTML = `
      <svg xmlns="http://www.w3.org/2000/svg" class="inline-block w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
      </svg>
      Copied!
    `
    button.disabled = true

    // Reset after 2 seconds
    setTimeout(() => {
      button.className = originalClasses
      button.innerHTML = originalHTML
      button.disabled = false
    }, 2000)
  }
}
