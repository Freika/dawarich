import { spectralMarkup } from "./spectral_material.js"

let sequence = 0

export function initializeAchievementMaterials(root) {
  const disposers = [...root.querySelectorAll(".ach-card-wrap")].map((el) => {
    const card = el.querySelector(".ach-spectral")
    const material = el.querySelector(".spectral-material")
    const svg = material?.querySelector(".spectral-fallback svg")
    const path = svg?.querySelector("path")
    if (!card || !svg || !path) return () => {}
    const result = spectralMarkup({
      silhouette: {
        viewbox: svg.getAttribute("viewBox"),
        path: path.getAttribute("d"),
      },
      key: el.dataset.achievementCardKeyValue,
      rarity: el.dataset.achievementCardRarityValue || "common",
      paperAsset: el.dataset.achievementCardPaperValue,
      foilAsset: el.dataset.achievementCardFoilValue,
      uid: `native-unlock-${++sequence}`,
    })
    if (!result) return () => {}
    material.innerHTML = result.html
    const locked = el.dataset.achievementCardLockedValue === "true"
    card.style.setProperty("--accent", locked ? "#899297" : result.accent)
    const stage = material.querySelector(".geo-stage")
    const fit = () => {
      if (!stage?.clientWidth || !stage.clientHeight) return
      const svg = stage.querySelector("svg")
      const box = svg.querySelector(".geo-fill").getBBox()
      const unit = Math.min(stage.clientWidth / 300, stage.clientHeight / 260)
      const width =
        2 * Math.max(Math.abs(box.x - 150), Math.abs(box.x + box.width - 150))
      const height =
        2 * Math.max(Math.abs(box.y - 130), Math.abs(box.y + box.height - 130))
      const scale = Math.max(
        0.05,
        Math.min(
          1.15,
          (stage.clientWidth - 8) / (width * unit),
          (stage.clientHeight - 8) / (height * unit),
        ),
      )
      svg.style.setProperty("--map-scale", scale.toFixed(4))
    }
    const observer = new ResizeObserver(fit)
    observer.observe(stage)
    fit()
    return () => observer.disconnect()
  })
  return () => {
    for (const dispose of disposers) dispose()
  }
}
