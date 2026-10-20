import { initializeAchievementMaterials } from "./material.js"

export function initializeAchievementCard(element) {
  const wrap = element.closest(".ach-card-wrap")
  const card = wrap.querySelector(".ach-spectral")
  const dispose = initializeAchievementMaterials({ querySelectorAll: () => [wrap] })
  const motion = matchMedia("(prefers-reduced-motion: reduce)")
  let frame, rect, pointer
  const leave = () => {
    cancelAnimationFrame(frame)
    frame = null
    rect = null
    card.style.removeProperty("--rx")
    card.style.removeProperty("--ry")
    for (const gradient of card.querySelectorAll("[data-spectrum]"))
      gradient.setAttribute("gradientTransform", "rotate(8 150 130)")
  }
  const move = (event) => {
    if (wrap.dataset.achievementCardLockedValue === "true" || motion.matches || event.pointerType === "touch") return
    rect ||= wrap.getBoundingClientRect()
    pointer = { x: event.clientX, y: event.clientY }
    if (frame) return
    frame = requestAnimationFrame(() => {
      frame = null
      const x = Math.max(-1, Math.min(1, ((pointer.x - rect.left) / rect.width) * 2 - 1))
      const y = Math.max(-1, Math.min(1, ((pointer.y - rect.top) / rect.height) * 2 - 1))
      card.style.setProperty("--rx", `${-y * 10}deg`)
      card.style.setProperty("--ry", `${x * 10}deg`)
      for (const gradient of card.querySelectorAll("[data-spectrum]"))
        gradient.setAttribute("gradientTransform", `rotate(${8 + x * 8 - y * 3} 150 130) translate(${x * 14} ${y * 8})`)
    })
  }
  const key = (event) => {
    if (event.key === " " && wrap.getAttribute("role") === "button") {
      event.preventDefault()
      wrap.click()
    }
  }
  wrap.addEventListener("pointermove", move)
  wrap.addEventListener("pointerleave", leave)
  wrap.addEventListener("keydown", key)
  return () => {
    dispose()
    leave()
    wrap.removeEventListener("pointermove", move)
    wrap.removeEventListener("pointerleave", leave)
    wrap.removeEventListener("keydown", key)
  }
}
