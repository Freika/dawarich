import { Controller } from "@hotwired/stimulus"
import Flash from "./flash_controller"

export default class extends Controller {
  static values = {
    text: String,
  }

  static targets = ["icon", "text"]

  copy() {
    const text = this.textValue

    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard
        .writeText(text)
        .then(() => this.handleSuccess())
        .catch(() => this.fallbackCopy(text))
      return
    }

    this.fallbackCopy(text)
  }

  fallbackCopy(text) {
    const textarea = document.createElement("textarea")
    textarea.value = text
    textarea.setAttribute("readonly", "")
    textarea.style.position = "fixed"
    textarea.style.top = "0"
    textarea.style.left = "0"
    textarea.style.opacity = "0"
    textarea.style.pointerEvents = "none"
    document.body.appendChild(textarea)

    textarea.focus()
    textarea.select()
    textarea.setSelectionRange(0, text.length)

    let succeeded = false
    try {
      succeeded = document.execCommand("copy")
    } catch (err) {
      console.error("Failed to copy text: ", err)
    }

    document.body.removeChild(textarea)

    if (succeeded) {
      this.handleSuccess()
    } else {
      Flash.show("error", "Failed to copy. Please copy manually.")
    }
  }

  handleSuccess() {
    this.showButtonFeedback()
    Flash.show("notice", "Copied to clipboard!")
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
