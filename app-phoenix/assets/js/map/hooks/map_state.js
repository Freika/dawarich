export const MapState = {
  beforeUpdate() {
    this.ownedState = this.el.dataset.mapState
  },
  updated() {
    const state = this.mapOwner?.presentationState ?? this.ownedState
    if (state) this.el.dataset.mapState = state
  },
}
