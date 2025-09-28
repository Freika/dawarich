import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["confirmButton", "cancelButton"]
  static values = {
    action: String,
    memberEmail: String,
    familyName: String
  }

  connect() {
    this.setupConfirmationMessages()
  }

  setupConfirmationMessages() {
    const confirmButtons = this.element.querySelectorAll('[data-confirm]')

    confirmButtons.forEach(button => {
      button.addEventListener('click', (event) => {
        const action = button.dataset.action
        const confirmMessage = this.getConfirmationMessage(action)

        if (!confirm(confirmMessage)) {
          event.preventDefault()
          return false
        }
      })
    })
  }

  getConfirmationMessage(action) {
    switch(action) {
      case 'leave-family':
        return `Are you sure you want to leave "${this.familyNameValue}"? You'll need a new invitation to rejoin.`
      case 'delete-family':
        return `Are you sure you want to delete "${this.familyNameValue}"? This action cannot be undone.`
      case 'remove-member':
        return `Are you sure you want to remove ${this.memberEmailValue} from the family?`
      case 'cancel-invitation':
        return `Are you sure you want to cancel the invitation to ${this.memberEmailValue}?`
      default:
        return 'Are you sure you want to perform this action?'
    }
  }

  showLoadingState(button, action) {
    const originalText = button.innerHTML
    button.disabled = true

    const loadingText = this.getLoadingText(action)
    button.innerHTML = `
      <span class="loading loading-spinner loading-sm"></span>
      ${loadingText}
    `

    // Store original text to restore if needed
    button.dataset.originalText = originalText
  }

  getLoadingText(action) {
    switch(action) {
      case 'leave-family':
        return 'Leaving family...'
      case 'delete-family':
        return 'Deleting family...'
      case 'remove-member':
        return 'Removing member...'
      case 'cancel-invitation':
        return 'Cancelling invitation...'
      default:
        return 'Processing...'
    }
  }

  onConfirmedAction(event) {
    const button = event.currentTarget
    const action = button.dataset.action

    this.showLoadingState(button, action)
  }
}