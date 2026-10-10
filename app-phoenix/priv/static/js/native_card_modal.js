import CardModal from "rails_card_modal"

export default class extends CardModal {
  open(event) {
    super.open(event)
    this.managerUrl = this.moved?.dataset.shareManager || null
    if (this.hasUnshareBtnTarget) this.unshareBtnTarget.href = this.managerUrl
  }

  async setSharing(enabled) {
    if (enabled && this.shared && this.shareUrl) return true
    if (this.managerUrl) window.location.assign(this.managerUrl)
    return false
  }

  unshare() {
    if (this.managerUrl) window.location.assign(this.managerUrl)
  }
}
