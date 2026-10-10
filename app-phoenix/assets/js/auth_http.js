import { initializeAuthChrome } from "./http/auth_chrome.js"
import { initializeAuthForms } from "./http/auth_forms.js"

let dispose
const mount = () => {
  dispose?.()
  const cleanup = [initializeAuthChrome(), initializeAuthForms()]
  let stopped = false
  const widget = document.querySelector("[data-auth-changelog]")
  if (widget)
    import("./hooks/changelog_widget.js").then(
      ({ initializeChangelogWidget }) => {
        if (!stopped) cleanup.push(initializeChangelogWidget(widget))
      },
    )
  const achievements = document.querySelector("[data-auth-achievements]")
  if (achievements)
    import("./hooks/achievement_unlocks.js").then(
      ({ initializeAchievementUnlocks }) => {
        if (!stopped) cleanup.push(initializeAchievementUnlocks(achievements))
      },
    )
  dispose = () => {
    stopped = true
    for (const stop of cleanup) stop()
  }
}
window.addEventListener("pageshow", mount)
window.addEventListener("pagehide", () => dispose?.())
mount()
