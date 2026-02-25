import { Controller } from "@hotwired/stimulus"
import { Picker } from "emoji-mart"

// Emoji Picker Controller
// Based on RailsBlocks pattern: https://railsblocks.com/docs/emoji-picker
export default class extends Controller {
  static targets = ["input", "button", "pickerContainer"]
  static values = {
    autoSubmit: { type: Boolean, default: true },
  }

  connect() {
    this.picker = null
    this.setupKeyboardListeners()
  }

  disconnect() {
    this.removePicker()
    this.removeKeyboardListeners()
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    if (this.pickerContainerTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    if (!this.picker) {
      this.createPicker()
    }

    this.pickerContainerTarget.classList.remove("hidden")
    this.setupOutsideClickListener()
  }

  close() {
    this.pickerContainerTarget.classList.add("hidden")
    this.removeOutsideClickListener()
  }

  createPicker() {
    this.picker = new Picker({
      onEmojiSelect: this.onEmojiSelect.bind(this),
      theme: this.getTheme(),
      previewPosition: "none",
      skinTonePosition: "search",
      maxFrequentRows: 2,
      perLine: 8,
      navPosition: "bottom",
      categories: [
        "frequent",
        "people",
        "nature",
        "foods",
        "activity",
        "places",
        "objects",
        "symbols",
        "flags",
      ],
    })

    this.pickerContainerTarget.appendChild(this.picker)
  }

  onEmojiSelect(emoji) {
    if (!emoji || !emoji.native) return

    // Update input value
    this.inputTarget.value = emoji.native

    // Update button to show selected emoji
    if (this.hasButtonTarget) {
      // Find the display element (could be a span or the button itself)
      const display =
        this.buttonTarget.querySelector("[data-emoji-picker-display]") ||
        this.buttonTarget
      display.textContent = emoji.native
    }

    // Close picker
    this.close()

    // Auto-submit if enabled
    if (this.autoSubmitValue) {
      this.submitForm()
    }

    // Dispatch custom event for advanced use cases
    this.dispatch("select", { detail: { emoji: emoji.native } })
  }

  submitForm() {
    const form = this.element.closest("form")
    if (form && !form.requestSubmit) {
      // Fallback for older browsers
      form.submit()
    } else if (form) {
      form.requestSubmit()
    }
  }

  clearEmoji(event) {
    event?.preventDefault()
    this.inputTarget.value = ""

    if (this.hasButtonTarget) {
      const display =
        this.buttonTarget.querySelector("[data-emoji-picker-display]") ||
        this.buttonTarget
      // Reset to default emoji or icon
      const defaultIcon = this.buttonTarget.dataset.defaultIcon || "😀"
      display.textContent = defaultIcon
    }

    this.dispatch("clear")
  }

  getTheme() {
    // Detect dark mode from document
    if (
      document.documentElement.getAttribute("data-theme") === "dark" ||
      document.documentElement.classList.contains("dark")
    ) {
      return "dark"
    }
    return "light"
  }

  setupKeyboardListeners() {
    this.handleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.handleKeydown)
  }

  removeKeyboardListeners() {
    document.removeEventListener("keydown", this.handleKeydown)
  }

  handleKeydown(event) {
    // Close on Escape
    if (
      event.key === "Escape" &&
      !this.pickerContainerTarget.classList.contains("hidden")
    ) {
      this.close()
    }

    // Clear on Delete/Backspace (when picker is open)
    if (
      (event.key === "Delete" || event.key === "Backspace") &&
      !this.pickerContainerTarget.classList.contains("hidden") &&
      event.target === this.inputTarget
    ) {
      event.preventDefault()
      this.clearEmoji()
    }
  }

  setupOutsideClickListener() {
    this.handleOutsideClick = this.handleOutsideClick.bind(this)
    // Use setTimeout to avoid immediate triggering from the toggle click
    setTimeout(() => {
      document.addEventListener("click", this.handleOutsideClick)
    }, 0)
  }

  removeOutsideClickListener() {
    if (this.handleOutsideClick) {
      document.removeEventListener("click", this.handleOutsideClick)
    }
  }

  handleOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  removePicker() {
    if (this.picker?.remove) {
      this.picker.remove()
    }
    this.picker = null
  }
}
