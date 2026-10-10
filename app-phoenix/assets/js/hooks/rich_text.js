const loadEditor = () =>
  Promise.all([import("trix"), import("../editor/attachments.js")]).then(
    ([, attachments]) => attachments,
  )

export const RichText = {
  loadEditor,
  mounted() {
    this.alive = true
    this.revision = Number(this.el.dataset.revision || 0)
    this.input = this.el.querySelector("input[type='hidden']")
    this.listeners = {
      "trix-change": () =>
        this.input.dispatchEvent(new Event("input", { bubbles: true })),
      "trix-attachment-add": (event) => this.attachments?.add(event.attachment),
      "trix-attachment-remove": (event) =>
        this.attachments?.remove(event.attachment),
    }
    this.handleEvent("rich_text:reset", (payload) => this.reset(payload))
    this.loading = this.loadEditor()
      .then(({ RichAttachments }) => {
        if (!this.alive) return
        this.attachments = new RichAttachments(this)
        this.editor = this.el.querySelector("trix-editor")
        for (const [name, fn] of Object.entries(this.listeners))
          this.editor.addEventListener(name, fn)
        this.el.dataset.editorReady = "true"
      })
      .catch(() => {
        if (this.alive) this.el.dataset.editorError = "true"
      })
  },
  statusElement() {
    return this.el.querySelector("[data-rich-status]")
  },
  reset({ id, revision, value }) {
    if (id !== this.el.id || !(revision > this.revision)) return
    this.revision = revision
    this.input.value = value
    this.editor?.editor?.loadHTML(value)
  },
  destroyed() {
    this.alive = false
    this.attachments?.cancelAll()
    if (!this.editor) return
    for (const [name, fn] of Object.entries(this.listeners))
      this.editor.removeEventListener(name, fn)
  },
}
