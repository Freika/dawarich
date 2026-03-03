import BaseController from "./base_controller"

export default class extends BaseController {
  static targets = ["form"]

  selectPlace() {
    this.formTarget.requestSubmit()
  }
}
