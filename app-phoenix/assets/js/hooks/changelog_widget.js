export function initializeChangelogWidget(el, doc = document) {
  if (doc.getElementById("chibichange-loader")) return () => {}
  const script = doc.createElement("script")
  script.id = "chibichange-loader"
  script.src = el.dataset.changelogWidgetSrcValue
  script.async = true
  script.dataset.slug = el.dataset.changelogWidgetSlugValue
  script.dataset.version = el.dataset.changelogWidgetVersionValue
  script.dataset.consent = "granted"
  script.dataset.mount = "#chgtool-mount"
  doc.head.appendChild(script)
  return () => script.remove()
}

export const ChangelogWidget = {
  mounted() {
    this.dispose = initializeChangelogWidget(this.el)
  },
  destroyed() {
    this.dispose?.()
  },
}
