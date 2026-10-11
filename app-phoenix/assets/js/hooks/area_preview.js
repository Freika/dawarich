export const AreaPreview = {
  mounted() {
    this.root = this.el.closest("[data-native-map-root]")
    this.preview = () => {
      if (this.root?.querySelector("#native-area-dialog") !== this.el) return
      const values = Object.fromEntries(
        ["latitude", "longitude", "radius"].map((name) => [
          name,
          Number(this.el.querySelector(`[name="area[${name}]"]`)?.value),
        ]),
      )
      const { latitude, longitude } = values
      const detail =
        Number.isFinite(latitude) &&
        Number.isFinite(longitude) &&
        Math.abs(latitude) <= 90 &&
        Math.abs(longitude) <= 180
          ? values
          : null
      this.root.dispatchEvent(
        new CustomEvent("native:area-preview", { detail }),
      )
    }
    this.el.addEventListener("input", this.preview)
    this.preview()
  },
  updated() {
    this.preview()
  },
  destroyed() {
    this.el.removeEventListener("input", this.preview)
    const current = this.root?.querySelector("#native-area-dialog")
    if (this.root && (!current || current === this.el)) {
      this.root.dispatchEvent(
        new CustomEvent("native:area-preview", { detail: null }),
      )
    }
  },
}
