const ACTIVE = { original: "btn-warning", matched: "btn-success" }

async function defaultLoader() {
  const [maplibre, demo, styles] = await Promise.all([
    import("/maplibre/6.4.1/maplibre-gl.mjs"),
    import("../demo/map_matching_demo.js"),
    import("../demo/map_style.js"),
  ])
  return { maplibre, demo, style: await styles.demoStyle() }
}

export const MapMatchingDemo = {
  async mounted() {
    this.mode = "matched"
    this.buttons = Array.from(this.el.querySelectorAll("button[data-mode]"))
    this.select = (event) => this.showMode(event.currentTarget.dataset.mode)
    for (const button of this.buttons)
      button.addEventListener("click", this.select)
    this.updateButtons()

    try {
      const { maplibre, demo, style } = await (this.loader || defaultLoader)()
      if (this.destroyedAt) return
      this.demo = demo
      this.map = demo.mountDemoMap(
        this.el.querySelector("[data-demo-map]"),
        maplibre,
        style,
        () => {
          this.routeReady = true
          this.showMode(this.mode)
          this.el.querySelector("[data-demo-loading]")?.remove()
        },
      )
    } catch (error) {
      console.error("Map matching demo failed to initialize:", error)
    }
  },
  destroyed() {
    this.destroyedAt = true
    for (const button of this.buttons || [])
      button.removeEventListener("click", this.select)
    this.map?.remove()
    this.map = null
  },
  showMode(mode) {
    if (!(mode in ACTIVE)) return
    this.mode = mode
    this.updateButtons()
    if (this.map && this.routeReady) this.demo.showMode(this.map, mode)
  },
  updateButtons() {
    for (const button of this.buttons) {
      const active = button.dataset.mode === this.mode
      button.setAttribute("aria-pressed", String(active))
      button.classList.toggle("btn-ghost", !active)
      button.classList.toggle("btn-outline", !active)
      button.classList.toggle(ACTIVE[button.dataset.mode], active)
    }
  },
}
