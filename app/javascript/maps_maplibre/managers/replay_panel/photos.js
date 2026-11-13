import { ReplayPhotoStack } from "maps_maplibre/components/replay_photo_stack"
import { ReplayPhotoLayer } from "maps_maplibre/layers/replay_photo_layer"
import { ReplayPhotoIndex } from "maps_maplibre/managers/replay_photo_index"

/**
 * Photos revealed along the replay as the marker passes them.
 * Mixed into ReplayPanel; `this` is the ReplayPanel.
 */
export const photos = {
  setupReplayPhotos() {
    if (!this._getPhotos) return

    const photos = this._getPhotos()
    if (!photos?.length) return

    this._photoIndex = new ReplayPhotoIndex({
      photos,
      timezone: this.timezone,
      getCoordinates: (photo) => this.replayManager.getCoordinates(photo),
    })
    if (!this._photoIndex.hasPhotos()) {
      this._photoIndex = null
      return
    }

    this._replayPhotoLayer = new ReplayPhotoLayer(this.map, {
      timezone: this.timezone,
    })
    this._replayPhotoLayer.setPhotos(this._photoIndex.allPhotos())
    this._replayPhotoStack = new ReplayPhotoStack(this.map, {
      timezone: this.timezone,
    })
    this._onReplayPhotosActive(true)
  },

  updateRevealedPhotos(playheadMs) {
    if (playheadMs === null || playheadMs === undefined) return
    this._lastPlayheadMs = playheadMs
    if (!this._replayPhotoLayer || !this._photoIndex) return

    const day = this.replayManager?.getCurrentDay()
    if (!day) return

    const revealed = this._photoIndex.revealedPhotos(day, playheadMs)
    const revealIds = new Set(revealed.map((photo) => photo.id))
    for (const photo of this._photoIndex.dayPhotos(day)) {
      if (revealIds.has(photo.id)) {
        this._replayPhotoLayer.reveal(photo.id)
      } else {
        this._replayPhotoLayer.hide(photo.id)
      }
    }
    this._replayPhotoStack?.sync(revealed)
  },

  resetReplayPhotos() {
    if (this._replayPhotoLayer) this._replayPhotoLayer.hideAll()
    if (this._replayPhotoStack) this._replayPhotoStack.clear()
  },

  refreshReplayPhotos() {
    if (!this.replayManager) return
    this.teardownReplayPhotos()
    this.setupReplayPhotos()
    if (this._lastPlayheadMs !== null && this._lastPlayheadMs !== undefined) {
      this.updateRevealedPhotos(this._lastPlayheadMs)
    }
  },

  teardownReplayPhotos() {
    if (this._replayPhotoLayer) {
      this._replayPhotoLayer.clear()
      this._replayPhotoLayer = null
    }
    if (this._replayPhotoStack) {
      this._replayPhotoStack.destroy()
      this._replayPhotoStack = null
    }
    if (this._photoIndex) {
      this._photoIndex = null
      this._onReplayPhotosActive(false)
    }
  },
}
