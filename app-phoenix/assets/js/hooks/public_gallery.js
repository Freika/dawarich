export const PublicGallery = {
  mounted() {
    this.galleryToggle = () => {
      this.pushEvent("public:gallery", {
        day: this.el.dataset.publicDay,
        open: this.el.open,
      })
    }
    this.el.addEventListener("toggle", this.galleryToggle)
    if (this.el.open) this.galleryToggle()
  },
  destroyed() {
    this.el.removeEventListener("toggle", this.galleryToggle)
  },
}
