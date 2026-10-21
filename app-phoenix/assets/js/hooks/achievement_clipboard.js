import { copyText } from "./clipboard.js"

export const AchievementClipboard = {
  mounted() {
    this.generation = 0
    this.copy = async (event) => {
      event.preventDefault()
      const generation = ++this.generation
      const copied = await copyText(this.el.dataset.nativeClipboardText || "")
      if (generation !== this.generation) return
      this.el.textContent = copied ? this.el.dataset.nativeCopiedLabel : this.el.dataset.nativeFailedLabel
      this.timer = setTimeout(() => {
        if (generation === this.generation) this.el.textContent = this.label
      }, 1500)
    }
    this.label = this.el.textContent
    this.el.addEventListener("click", this.copy)
  },
  destroyed() {
    this.generation++
    clearTimeout(this.timer)
    this.el.removeEventListener("click", this.copy)
  },
}
