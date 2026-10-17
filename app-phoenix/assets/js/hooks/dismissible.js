const storageKey = (el) => `dismissed:${el.dataset.dismissibleKeyValue}`

const read = (key) => {
  try {
    return localStorage.getItem(key)
  } catch (_error) {
    return null
  }
}

export const Dismissible = {
  mounted() {
    this.apply()
    this.dismiss = (event) => {
      if (!event.target.closest("button")) return
      try {
        localStorage.setItem(storageKey(this.el), "1")
      } catch (_error) {}
      this.el.hidden = true
    }
    this.el.addEventListener("click", this.dismiss)
  },
  updated() {
    this.apply()
  },
  apply() {
    if (read(storageKey(this.el)) === "1") this.el.hidden = true
  },
  destroyed() {
    this.el.removeEventListener("click", this.dismiss)
  },
}
