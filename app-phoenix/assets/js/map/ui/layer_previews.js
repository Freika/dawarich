import { mapTranslate } from "./translate.js"

export function installLayerPreviews({ owner, root }) {
  const previews = new Map(), enabled = new Map()
  const update = owner.update
  owner.update = config => update.call(owner, { ...config, ...Object.fromEntries(enabled) })
  const translate = mapTranslate(() => owner.config)
  let destroyed = false
  const click = async event => {
    const toggle = event.target?.closest?.("[data-native-preview-layer]")
    if (!toggle || !root?.contains(toggle)) return
    const { startLayerPreview } = await import("./layer_gate.js")
    const { UpgradeBanner } = await import("./upgrade_banner.js")
    if (destroyed) return
    const layerName = toggle.dataset.nativePreviewLayer
    const key = toggle.dataset.nativePreviewKey
    previews.get(key)?.()
    previews.delete(key)
    const hideFn = () => { enabled.delete(key); return owner.update({ ...owner.config, [key]: false }) }
    if (!toggle.checked) { hideFn(); return }
    enabled.set(key, true)
    const cancel = await startLayerPreview({
      layerName, toggle, translate,
      showFn: async () => {
        const state = await owner.update({ ...owner.config, [key]: true })
        if (state === "failed") throw new Error()
      },
      hideFn,
      onEnd: () => {
        previews.delete(key)
        UpgradeBanner.show({ message: translate("layer_preview.ended", { layer: layerName }), upgradeUrl: owner.config.upgradeUrl, utmContent: `layer_preview_${layerName.toLowerCase().replace(/ /g, "_")}`, translate })
      },
    })
    if (destroyed) cancel()
    else if (toggle.checked) previews.set(key, cancel)
    else enabled.delete(key)
  }
  root?.addEventListener("click", click)
  return () => {
    destroyed = true
    root?.removeEventListener("click", click)
    for (const cancel of previews.values()) cancel()
    previews.clear()
    enabled.clear()
    owner.update = update
  }
}
