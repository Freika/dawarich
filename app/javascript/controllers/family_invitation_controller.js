import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "email", "submitButton", "errorMessage"]
  static values = { maxMembers: Number, currentMembers: Number }

  connect() {
    this.validateForm()
  }

  validateForm() {
    const email = this.emailTarget.value.trim()
    const isValid = this.isValidEmail(email) && this.canInviteMoreMembers()

    this.submitButtonTarget.disabled = !isValid

    if (email && !this.isValidEmail(email)) {
      this.showError("Please enter a valid email address")
    } else if (!this.canInviteMoreMembers()) {
      this.showError(`Family is full (${this.currentMembersValue}/${this.maxMembersValue} members)`)
    } else {
      this.hideError()
    }
  }

  onEmailInput() {
    this.validateForm()
  }

  isValidEmail(email) {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
    return emailRegex.test(email)
  }

  canInviteMoreMembers() {
    return this.currentMembersValue < this.maxMembersValue
  }

  showError(message) {
    if (this.hasErrorMessageTarget) {
      this.errorMessageTarget.textContent = message
      this.errorMessageTarget.classList.remove("hidden")
    }
  }

  hideError() {
    if (this.hasErrorMessageTarget) {
      this.errorMessageTarget.classList.add("hidden")
    }
  }

  onSubmit(event) {
    if (!this.isValidEmail(this.emailTarget.value.trim()) || !this.canInviteMoreMembers()) {
      event.preventDefault()
      this.validateForm()
      return false
    }

    // Show loading state
    this.submitButtonTarget.disabled = true
    this.submitButtonTarget.innerHTML = `
      <span class="loading loading-spinner loading-sm"></span>
      Sending invitation...
    `
  }
}