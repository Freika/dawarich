import { bindTool } from "./host_tools.js"

export function installStudios({ element, owner, lifetime }) {
  const root = element.closest?.("[data-native-map-root]")
  const dispatch = (studio, detail) => {
    root
      ?.querySelector(`#native-${studio}-studio`)
      ?.dispatchEvent(
        new CustomEvent(`dawarich:${studio}-studio-open`, { detail }),
      )
  }
  const poster = () =>
    dispatch("poster", {
      source: owner.source,
      openVideo: (source) => dispatch("video", { source }),
      fallbackBounds: () => {
        if (owner.source.fixedRange) return null
        const b = owner.map?.getBounds()
        return b
          ? [
              [b.getWest(), b.getSouth()],
              [b.getEast(), b.getNorth()],
            ]
          : null
      },
    })
  owner.openStudio = (kind) => {
    if (kind === "poster") poster()
    if (kind === "video") dispatch("video", { source: owner.source })
  }
  lifetime.own(() => delete owner.openStudio)
  const switchStudio = (event) => {
    if (
      event.target === root?.querySelector("#native-video-studio") &&
      event.detail?.studio === "poster" &&
      event.detail.source === owner.source
    )
      poster()
  }
  root?.addEventListener("dawarich:studio-switch", switchStudio)
  lifetime.own(() =>
    root?.removeEventListener("dawarich:studio-switch", switchStudio),
  )
  bindTool(root, '[data-testid="map-button-poster"]', poster, lifetime)
  bindTool(
    root,
    '[data-testid="map-button-video"]',
    () => dispatch("video", { source: owner.source }),
    lifetime,
  )
}
