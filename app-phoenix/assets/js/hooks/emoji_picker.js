const loadPicker = () =>
  Promise.all([import("emoji-mart"), import("@emoji-mart/data")]).then(
    ([{ Picker }, { default: data }]) => ({ Picker, data }),
  )

export const EmojiPicker = {
  mounted() {
    this.button = this.el.querySelector("[data-emoji-toggle]")
    this.container = this.el.querySelector("[data-emoji-container]")
    this.input = this.el.querySelector("input[type='hidden']")
    this.toggle = (event) => {
      event.preventDefault()
      this.container.hidden ? this.open() : this.close()
    }
    this.outside = (event) => {
      if (!this.el.contains(event.target)) this.close()
    }
    this.escape = (event) => {
      if (event.key === "Escape") this.close()
    }
    this.button.addEventListener("click", this.toggle)
  },
  open() {
    this.container.hidden = false
    document.addEventListener("click", this.outside)
    document.addEventListener("keydown", this.escape)
    if (this.picker) return
    loadPicker().then(({ Picker, data }) => {
      if (this.destroyedAlready) return
      this.picker = new Picker({
        data,
        onEmojiSelect: (emoji) => this.select(emoji.native),
        theme: document.documentElement.dataset.theme?.endsWith("dark")
          ? "dark"
          : "light",
        previewPosition: "none",
        skinTonePosition: "search",
        maxFrequentRows: 2,
        perLine: 8,
        navPosition: "bottom",
      })
      this.container.appendChild(this.picker)
    })
  },
  close() {
    this.container.hidden = true
    document.removeEventListener("click", this.outside)
    document.removeEventListener("keydown", this.escape)
  },
  select(emoji) {
    this.input.value = emoji
    this.input.dispatchEvent(new Event("input", { bubbles: true }))
    this.close()
  },
  destroyed() {
    this.destroyedAlready = true
    this.close()
    this.button.removeEventListener("click", this.toggle)
    this.picker?.remove()
  },
}
