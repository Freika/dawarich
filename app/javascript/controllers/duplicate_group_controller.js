import { Controller } from "@hotwired/stimulus"

// One group of possible duplicates. The kept place must be part of the merge,
// a skipped place fades, and the merge button waits until something would
// move into the kept place.
export default class extends Controller {
  static targets = ["keep", "include", "submit"]

  connect() {
    this.sync()
  }

  sync() {
    const kept = this.keepTargets.find((keep) => keep.checked)?.value
    for (const keep of this.keepTargets) {
      keep
        .closest("[data-duplicate-card]")
        ?.toggleAttribute("data-keep", keep.checked)
    }
    for (const include of this.includeTargets) {
      if (include.value === kept) include.checked = true
      include
        .closest("[data-duplicate-card]")
        ?.toggleAttribute("data-skipped", !include.checked)
    }
    const merging = this.includeTargets.filter(
      (include) => include.checked && include.value !== kept,
    )
    this.submitTarget.disabled = !kept || merging.length === 0
  }
}
