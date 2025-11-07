import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]
  static values = { text: String }

  copy(event) {
    event.preventDefault()
    const text = event.currentTarget.dataset.copyText

    navigator.clipboard.writeText(text).then(() => {
      const button = event.currentTarget
      const originalHTML = button.innerHTML

      // Show "Copied!" feedback
      button.innerHTML = `
        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
          <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
        </svg>
        <span>Copied!</span>
      `

      // Restore original content after 2 seconds
      setTimeout(() => {
        button.innerHTML = originalHTML
      }, 2000)
    }).catch(err => {
      console.error('Failed to copy text: ', err)
    })
  }
}
