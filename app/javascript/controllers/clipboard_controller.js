import { Controller } from "@hotwired/stimulus"
import { translate } from "i18n"
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
      Flash.show(
        "error",
        translate("messages.failed_to_copy_please_copy_manually"),
      )
    }
  }

  handleSuccess() {
    this.showButtonFeedback()
    Flash.show("notice", translate("messages.copied_to_clipboard"))
  }

  showButtonFeedback() {
    const button = this.element
    const originalHTML = button.innerHTML

    // Lock the current dimensions so swapping the content doesn't resize the
    // button or break a join/input-group layout, then briefly show a check.
    const { width, height } = button.getBoundingClientRect()
    button.style.width = `${width}px`
    button.style.height = `${height}px`
    button.classList.add("btn-success")
    button.innerHTML = `
      <svg xmlns="http://www.w3.org/2000/svg" class="inline-block w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
      </svg>
    `
    button.disabled = true

    setTimeout(() => {
      button.style.width = ""
      button.style.height = ""
      button.classList.remove("btn-success")
      button.innerHTML = originalHTML
      button.disabled = false
    }, 1500)
  }
}
