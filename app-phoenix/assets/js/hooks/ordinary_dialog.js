export const OrdinaryDialog = {
  mounted() {
    this.el
      .querySelector?.("[data-native-dialog-initial-focus]")
      ?.focus({ preventScroll: true })
    this.onKey = (event) => {
      if (event.key !== "Tab") return
      const controls = [
        ...this.el.querySelectorAll(
          'button:not([disabled]),input:not([disabled]):not([type="hidden"]),textarea:not([disabled]),select:not([disabled]),a[href],[tabindex="0"]',
        ),
      ].filter((element) => element.getClientRects().length)
      const first = controls[0]
      const last = controls.at(-1)
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault()
        last.focus()
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault()
        first.focus()
      }
    }
    this.el.addEventListener("keydown", this.onKey)
  },
  destroyed() {
    this.el.removeEventListener("keydown", this.onKey)
  },
}
