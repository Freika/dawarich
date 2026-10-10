export const ChangelogWidget = {
  mounted() {
    if (document.getElementById("chibichange-loader")) return
    const script = document.createElement("script")
    script.id = "chibichange-loader"
    script.src = this.el.dataset.changelogWidgetSrcValue
    script.async = true
    script.dataset.slug = this.el.dataset.changelogWidgetSlugValue
    script.dataset.version = this.el.dataset.changelogWidgetVersionValue
    script.dataset.consent = "granted"
    script.dataset.mount = "#chgtool-mount"
    document.head.appendChild(script)
  },
}
