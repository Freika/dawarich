import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    selfHosted: Boolean
  }

  // Every controller that extends BaseController and uses initialize()
  // should call super.initialize()
  // Example:
  // export default class extends BaseController {
  //   initialize() {
  //     super.initialize()
  //   }
  // }
  initialize() {
    // Get the self-hosted value from the HTML root element
    if (!this.hasSelfHostedValue) {
      const selfHosted = document.documentElement.dataset.selfHosted === 'true'
      this.selfHostedValue = selfHosted
    }

    console.log(`Self-hosted mode in base controller: ${this.selfHostedValue}`)
  }
}
