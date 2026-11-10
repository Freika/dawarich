import { translate } from "i18n"
import { ReplayPanel } from "maps_maplibre/managers/replay_panel"
import { featureToPhoto } from "maps_maplibre/utils/feature_to_photo"

/** The main map's replay panel, created on first use. */
function ensureMapReplayPanel(controller) {
  controller.replayPanel ||= new ReplayPanel({
    controller,
    map: controller.map,
    timezone: controller.timezoneValue,
    distanceUnit: () => controller.settings?.distance_unit,
    markerLayer: () => controller.layerManager?.getLayer("replayMarker"),
    loadPoints: async () => {
      await controller.mapDataManager.ensurePointsLoaded()
      return controller._getLoadedPoints()
    },
    onPlayStateChange: updateTrackReplayButton,
    getPhotos: () => {
      const layer = controller.layerManager?.getLayer("photos")
      const features = layer?.visible ? layer.data?.features : null
      return features?.length ? features.map(featureToPhoto) : []
    },
    onReplayPhotosActive: (active) => {
      const layer = controller.layerManager?.getLayer("photos")
      if (!layer) return
      if (active) {
        controller._photosWasVisible = layer.visible
        layer.hide()
      } else if (controller._photosWasVisible) {
        layer.show()
      }
    },
  })
  return controller.replayPanel
}

/** The replay actions the main map's views bind. */
export class MapReplayActions {
  constructor(controller) {
    this.controller = controller
  }

  get panel() {
    return this.controller.replayPanel
  }

  async toggleReplay() {
    if (!this.controller.hasReplayPanelTarget) return
    await ensureMapReplayPanel(this.controller).toggle()
  }

  replayScrubberHover(event) {
    this.panel?.scrubberHover(event)
  }

  replayCyclePrev() {
    this.panel?.cyclePrev()
  }

  replayCycleNext() {
    this.panel?.cycleNext()
  }

  replayTogglePlayback() {
    this.panel?.togglePlayback()
  }

  replayRecenterFollow() {
    this.panel?.recenterFollow()
  }

  replaySpeedChange(event) {
    this.panel?.speedChange(event)
  }

  replayTrack(event) {
    if (!this.controller.hasReplayPanelTarget) return
    return replayTrackFrom(
      this.controller,
      event.currentTarget.dataset.trackStart,
    )
  }
}

/**
 * The timeline's track Replay button: pause a running replay, resume an open
 * one, or open the panel at the track's day and start minute.
 */
async function replayTrackFrom(controller, trackStart) {
  const panel = ensureMapReplayPanel(controller)

  if (panel.isPlaying) {
    panel.stopPlayback()
    return
  }

  const isVisible = !controller.replayPanelTarget.classList.contains("hidden")
  if (isVisible && panel.manager?.hasData()) {
    panel.startPlayback()
    return
  }

  if (!trackStart) return
  const trackDate = new Date(trackStart)
  if (Number.isNaN(trackDate.getTime())) return

  await panel.ensureOpen()
  if (!panel.manager?.hasData()) return

  const { manager } = panel
  panel.goToDay(manager.dayKey(trackDate))
  panel.setMinute(manager.minuteOfDay(trackDate))
  panel.startPlayback()
}

function updateTrackReplayButton(playing) {
  const playIcon = document.getElementById("track-replay-play-icon")
  const pauseIcon = document.getElementById("track-replay-pause-icon")
  const label = document.getElementById("track-replay-label")
  if (!playIcon || !pauseIcon || !label) return

  playIcon.classList.toggle("hidden", playing)
  pauseIcon.classList.toggle("hidden", !playing)
  label.textContent = translate(playing ? "replay.pause" : "replay.replay")
}
