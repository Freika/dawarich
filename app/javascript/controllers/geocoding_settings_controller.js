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
    "rpsInput",
    "rpsHint",
    "apiKeyWrapper",
  ]
  static values = {
    chibigeoHost: String,
    chibigeoBareHost: String,
    komootHost: String,
    httpsOnlyHosts: Array,
    rpsBounds: Object,
    rpsHints: Object,
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

    const kind = this.hostKind()
    this.chibigeoPanelTarget.hidden = kind !== "chibigeo"
    this.komootWarningTarget.hidden = kind !== "komoot"
    // komoot's public server takes no key; the field would only invite one.
    if (this.hasApiKeyWrapperTarget) {
      this.apiKeyWrapperTarget.hidden = kind === "komoot"
    }

    const locked = this.httpsOnlyHostsValue.includes(this.bareHost())
    if (locked) this.httpsToggleTarget.checked = true
    this.httpsToggleTarget.disabled = locked
    this.httpsHiddenTarget.value = locked ? "1" : "0"
    this.httpsLockedHintTarget.hidden = !locked

    this.refreshRps()
  }

  refreshRps() {
    if (!this.hasRpsInputTarget) return

    const choice = this.hostKind()
    const bounds = this.rpsBoundsValue[choice]
    const input = this.rpsInputTarget

    input.min = bounds.min
    input.max = bounds.max
    input.disabled = bounds.locked

    // A locked host has exactly one legal rate; a floored one cannot start
    // below it, and ChibiGeo starts everyone on the free tier.
    if (bounds.locked) {
      input.value = bounds.min
    } else if (input.value !== "" && Number(input.value) < bounds.min) {
      input.value = bounds.min
    } else if (input.value === "" && choice === "chibigeo") {
      input.value = bounds.min
    }

    this.rpsHintTarget.textContent = this.rpsHintsValue[choice]
  }

  hostKind() {
    const bareHost = this.bareHost()
    if (bareHost === this.komootHostValue) return "komoot"
    if (bareHost === this.chibigeoBareHostValue) return "chibigeo"
    return "custom"
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
