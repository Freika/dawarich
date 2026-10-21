export function initializePublicAchievements(
  root = document,
  target = window,
  load = () => import("./achievements/card.js"),
) {
  const elements = [...root.querySelectorAll('.spectral-material[phx-hook="AchievementMaterial"]')]
  let generation = 0, closed = false, active = false
  const owners = []
  const retire = () => {
    generation++
    active = false
    for (const [element, fallback, dispose] of owners) {
      dispose()
      element.innerHTML = fallback
    }
    owners.length = 0
  }
  const mount = () => {
    if (closed || active || !elements.length) return
    active = true
    const current = ++generation
    load().then(({ initializeAchievementCard }) => {
      if (closed || current !== generation) return
      for (const element of elements) {
        const fallback = element.innerHTML
        owners.push([element, fallback, initializeAchievementCard(element)])
      }
    }).catch(() => {
      if (current === generation) retire()
    })
  }
  const show = (event) => { if (event.persisted) mount() }
  target.addEventListener("pagehide", retire)
  target.addEventListener("pageshow", show)
  mount()
  return () => {
    closed = true
    target.removeEventListener("pagehide", retire)
    target.removeEventListener("pageshow", show)
    retire()
  }
}

if (typeof document !== "undefined") initializePublicAchievements()
