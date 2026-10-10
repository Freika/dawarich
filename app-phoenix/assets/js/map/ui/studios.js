import { bindTool } from "./host_tools.js"

export function installStudios({ element, owner, lifetime }) {
  const root = element.closest?.("[data-native-map-root]")
  const dispatch = (studio, detail) => {
    root?.querySelector(`#native-${studio}-studio`)?.dispatchEvent(
      new CustomEvent(`dawarich:${studio}-studio-open`, { detail }),
    )
  }
  const poster = () => dispatch("poster", {
    source: owner.source,
    fallbackBounds: () => {
      if (owner.source.fixedRange) return null
      const b = owner.map?.getBounds()
      return b ? [[b.getWest(), b.getSouth()], [b.getEast(), b.getNorth()]] : null
    },
  })
  bindTool(root, '[data-testid="map-button-poster"]', poster, lifetime)
  bindTool(root, '[data-testid="map-button-video"]', () => dispatch("video", { source: owner.source }), lifetime)
}
