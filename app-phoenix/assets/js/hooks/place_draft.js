export const PlaceDraft = {
  disconnected() {
    const form = this.el.querySelector(
      'form[data-form-status="idle"][data-place-id],form[data-native-form-status="idle"][data-native-place-id]',
    )
    if (!form) return
    const data = new FormData(form)
    const place = Object.fromEntries(
      ["name", "latitude", "longitude", "note"].map((key) => [
        key,
        data.get(`place[${key}]`) ?? "",
      ]),
    )
    place.tag_ids = data.getAll("place[tag_ids][]")
    this.draft = {
      user: this.el.dataset.nativeUserId ?? this.el.dataset.userId,
      id: form.dataset.nativePlaceId ?? form.dataset.placeId,
      place,
    }
  },
  destroyed() {
    this.draft = null
  },
  reconnected() {
    const saved = this.draft
    this.draft = null
    if (
      saved &&
      saved.user === (this.el.dataset.nativeUserId ?? this.el.dataset.userId)
    ) {
      this.pushEvent(
        this.el.dataset.nativeDraftEvent || "recover_place_draft",
        {
          id: saved.id,
          place: saved.place,
        },
      )
    }
  },
}
