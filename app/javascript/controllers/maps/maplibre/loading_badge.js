import { formatNumber, translate } from "i18n"

const COMPLETE_HIDE_MS = 1200
const STUCK_HIDE_MS = 800

/**
 * The map's "Loading N points · M tracks" badge. Each load reports the counts
 * it knows; a complete report fades the badge out.
 */
export class LoadingBadge {
  constructor(controller) {
    this.controller = controller
    this.counts = {}
    this._sourceCount = 0
  }

  get element() {
    return this.controller.hasProgressBadgeTarget
      ? this.controller.progressBadgeTarget
      : null
  }

  get textElement() {
    return this.controller.hasProgressBadgeTextTarget
      ? this.controller.progressBadgeTextTarget
      : null
  }

  show() {
    this._sourceCount = 0
    this.element?.classList.remove("complete", "pop")
    this.element?.classList.add("visible")
    if (this.textElement) {
      this.textElement.textContent = translate("common.loading")
    }
  }

  hide() {
    this.element?.classList.remove("visible")
  }

  /** Show the badge for one source that has started loading. */
  start(source) {
    this.show()
    this.update({ counts: { [source]: 0 }, isComplete: false })
  }

  /** Report the final count for one source and fade the badge out. */
  finish(source, count) {
    this.update({ counts: { [source]: count }, isComplete: true })
  }

  update({ counts, isComplete = false }) {
    this.counts = counts
    const text = this.textElement
    if (!text) return

    const parts = Object.entries(counts || {}).map(([source, count]) =>
      translate(`loading_sources.${source}`, {
        count,
        formatted_count: formatNumber(count),
      }),
    )

    const { settings, familyManager } = this.controller
    if (settings?.familyEnabled && counts?.family === undefined) {
      const familyCount = familyManager.memberCount
      parts.push(
        translate("loading_sources.family", {
          count: familyCount,
          formatted_count: formatNumber(familyCount),
        }),
      )
    }

    // A new source appearing restarts the pop animation.
    const badge = this.element
    if (badge && parts.length > this._sourceCount) {
      badge.classList.remove("pop")
      void badge.offsetWidth
      badge.classList.add("pop")
    }
    this._sourceCount = parts.length

    text.textContent =
      parts.length > 0 ? parts.join(" · ") : translate("common.loading")

    if (isComplete) {
      badge?.classList.add("complete")
      this._sourceCount = 0
      setTimeout(() => this.hide(), COMPLETE_HIDE_MS)
    }
  }

  /** Fade out a badge that no source completed, e.g. with every layer off. */
  dismissIfIncomplete() {
    const badge = this.element
    if (!badge?.classList.contains("visible")) return
    if (badge.classList.contains("complete")) return

    badge.classList.add("complete")
    setTimeout(() => this.hide(), STUCK_HIDE_MS)
  }
}
