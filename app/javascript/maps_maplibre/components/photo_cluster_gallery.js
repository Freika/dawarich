import { translate } from "i18n"
import { PhotoPopupFactory } from "./photo_popup"

export const PHOTO_CLUSTER_PAGE_SIZE = 24

/** A bounded, keyboard-accessible view of one source's cluster leaves. */
export class PhotoClusterGallery {
  constructor({ loadPage, total, timezone, returnFocus, onClose }) {
    Object.assign(this, { loadPage, total, timezone, returnFocus, onClose })
    this.request = 0
    this.offset = 0
    this.dialog = document.createElement("dialog")
    this.dialog.className = "photo-cluster-gallery"
    this.dialog.setAttribute("aria-label", translate("photo_cluster.title"))
    this.dialog.addEventListener("close", () => this.destroy())
    this.dialog.addEventListener("cancel", (event) => {
      event.preventDefault()
      this.close()
    })
    this.dialog.addEventListener("click", (event) => {
      if (event.target === this.dialog) {
        const rect = this.dialog.getBoundingClientRect()
        if (
          event.clientX < rect.left ||
          event.clientX > rect.right ||
          event.clientY < rect.top ||
          event.clientY > rect.bottom
        )
          this.close()
      }
    })

    const header = document.createElement("header")
    const title = document.createElement("h2")
    title.textContent = translate("photo_cluster.title")
    this.closeButton = this.button("close", () => this.close())
    header.append(title, this.closeButton)
    this.status = document.createElement("p")
    this.status.setAttribute("role", "status")
    this.content = document.createElement("div")
    this.content.className = "photo-cluster-gallery__content"
    this.footer = document.createElement("footer")
    this.previous = this.button("previous", () =>
      this.showPage(this.offset - PHOTO_CLUSTER_PAGE_SIZE),
    )
    this.next = this.button("next", () =>
      this.showPage(this.offset + PHOTO_CLUSTER_PAGE_SIZE),
    )
    this.footer.append(this.previous, this.next)
    this.dialog.append(header, this.status, this.content, this.footer)
  }

  button(key, action) {
    const button = document.createElement("button")
    button.type = "button"
    button.textContent = translate(`photo_cluster.${key}`)
    button.addEventListener("click", action)
    return button
  }

  open() {
    document.body.append(this.dialog)
    this.dialog.showModal()
    this.closeButton.focus()
    void this.showPage(0)
    return this
  }

  async showPage(offset) {
    if (this.destroyed) return
    const request = ++this.request
    this.offset = Math.max(0, offset)
    this.content.replaceChildren()
    this.footer.hidden = false
    this.previous.disabled = true
    this.next.disabled = true
    this.status.textContent = translate("photo_cluster.loading")
    this.content.setAttribute("aria-busy", "true")
    try {
      const leaves = await this.loadPage(PHOTO_CLUSTER_PAGE_SIZE, this.offset)
      if (this.destroyed || request !== this.request) return
      this.content.removeAttribute("aria-busy")
      this.status.textContent = leaves.length
        ? translate("photo_cluster.range", {
            start: this.offset + 1,
            end: this.offset + leaves.length,
            total: this.total,
          })
        : translate("photo_cluster.empty")
      const grid = document.createElement("div")
      grid.className = "photo-cluster-gallery__grid"
      for (const leaf of leaves) {
        const properties = leaf.properties || {}
        const button = document.createElement("button")
        button.type = "button"
        button.className = "photo-cluster-gallery__thumbnail"
        const label = properties.filename || translate("map_info.photo")
        button.setAttribute("aria-label", label)
        const image = document.createElement("img")
        image.alt = label
        image.loading = "lazy"
        image.decoding = "async"
        image.addEventListener(
          "error",
          () => {
            image.replaceWith(
              document.createTextNode(translate("photo_cluster.image_error")),
            )
          },
          { once: true },
        )
        // Reuse the protected proxy URL, including its authorization and source.
        // Never fetch originals or construct integration-server URLs here.
        if (properties.thumbnail_url) image.src = properties.thumbnail_url
        else image.alt = translate("photo_cluster.image_error")
        button.append(image)
        button.addEventListener("click", () =>
          this.showPhoto(properties, grid, button),
        )
        grid.append(button)
      }
      this.content.append(grid)
      this.previous.disabled = this.offset === 0
      this.next.disabled =
        !leaves.length || this.offset + leaves.length >= this.total
    } catch (_error) {
      if (this.destroyed || request !== this.request) return
      this.content.removeAttribute("aria-busy")
      this.status.textContent = translate("photo_cluster.error")
      this.content.append(
        this.button("retry", () => this.showPage(this.offset)),
      )
      this.previous.disabled = this.offset === 0
    }
  }

  showPhoto(properties, grid, thumbnail) {
    const back = this.button("back", () => {
      this.content.replaceChildren(grid)
      this.footer.hidden = false
      thumbnail.focus()
    })
    const preview = document.createElement("div")
    preview.className = "photo-cluster-gallery__preview"
    preview.innerHTML = PhotoPopupFactory.createPhotoPopup(
      properties,
      this.timezone,
    )
    const image = preview.querySelector("img")
    image?.addEventListener(
      "error",
      () => {
        image.replaceWith(
          document.createTextNode(translate("photo_cluster.image_error")),
        )
      },
      { once: true },
    )
    this.content.replaceChildren(back, preview)
    this.footer.hidden = true
    back.focus()
  }

  close() {
    this.dialog.close()
    this.destroy()
  }

  destroy() {
    if (this.destroyed) return
    this.destroyed = true
    ++this.request
    this.dialog.remove()
    this.content.replaceChildren()
    this.onClose?.()
    if (this.returnFocus?.isConnected)
      this.returnFocus.focus({ preventScroll: true })
  }
}
