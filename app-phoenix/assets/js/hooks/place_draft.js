let draft
export const PlaceDraft = {
  disconnected() {
    const form = this.el.querySelector('form[data-form-status="idle"][data-place-id]')
    if (!form) return
    const data = new FormData(form)
    const place = Object.fromEntries(
      ["name", "latitude", "longitude", "note"].map((key) => [key, data.get(`place[${key}]`) ?? ""]),
    )
    place.tag_ids = data.getAll("place[tag_ids][]")
    draft = { user: this.el.dataset.userId, id: form.dataset.placeId, place }
  },
  reconnected() {
    const saved = draft
    draft = null
    if (saved?.user === this.el.dataset.userId) {
      this.pushEvent("recover_place_draft", { id: saved.id, place: saved.place })
    }
  },
}
