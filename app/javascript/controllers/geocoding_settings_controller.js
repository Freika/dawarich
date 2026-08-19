import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "select",
    "fieldset",
    "hostChoice",
    "hostInput",
    "customHostWrapper",
    "komootWarning",
    "chibigeoPanel",
    "httpsToggle",
    "httpsHidden",
    "httpsLockedHint",
  ]
  static values = {
    chibigeoHost: String,
    chibigeoBareHost: String,
    komootHost: String,
    httpsOnlyHosts: Array,
  }

  connect() {
    this.providerChanged()
  }

  providerChanged() {
    const provider = this.selectTarget.value
    for (const fieldset of this.fieldsetTargets) {
      fieldset.hidden = fieldset.dataset.provider !== provider
    }
    this.refresh()
  }

  choiceChanged() {
    const choice = this.checkedChoice()
    if (choice === "chibigeo") {
      this.hostInputTarget.value = this.chibigeoHostValue
    } else if (choice === "komoot") {
      this.hostInputTarget.value = this.komootHostValue
    } else if (this.isPresetHost()) {
      this.hostInputTarget.value = ""
    }
    this.customHostWrapperTarget.hidden = choice !== "custom"
    this.refresh()
  }

  hostChanged() {
    this.refresh()
  }

  refresh() {
    if (!this.hasHostInputTarget) return

    for (const radio of this.hostChoiceTargets) {
      const row = radio.closest("label")
      row.classList.toggle("border-primary/60", radio.checked)
      row.classList.toggle("border-base-content/10", !radio.checked)
    }

    const bareHost = this.bareHost()
    this.chibigeoPanelTarget.hidden = bareHost !== this.chibigeoBareHostValue
    this.komootWarningTarget.hidden = bareHost !== this.komootHostValue

    const locked = this.httpsOnlyHostsValue.includes(bareHost)
    if (locked) this.httpsToggleTarget.checked = true
    this.httpsToggleTarget.disabled = locked
    this.httpsHiddenTarget.value = locked ? "1" : "0"
    this.httpsLockedHintTarget.hidden = !locked
  }

  checkedChoice() {
    const checked = this.hostChoiceTargets.find((radio) => radio.checked)
    return checked ? checked.value : "chibigeo"
  }

  isPresetHost() {
    const bareHost = this.bareHost()
    return (
      bareHost === this.chibigeoBareHostValue ||
      bareHost === this.komootHostValue
    )
  }

  bareHost() {
    return this.hostInputTarget.value
      .trim()
      .toLowerCase()
      .replace(/^https?:\/\//, "")
      .split("/")[0]
      .split(":")[0]
  }
}
