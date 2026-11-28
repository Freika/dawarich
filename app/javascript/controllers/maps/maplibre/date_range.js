import { anomaliesVisible } from "maps_maplibre/utils/layer_dependencies"
import { parseTimestamp } from "maps_maplibre/utils/realtime_date_filter"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"
import { DateManager } from "./date_manager"

/**
 * The map's selected date range. The range itself stays in the controller's
 * startDateValue / endDateValue, which layers, the private E2E suite and
 * other controllers read.
 */
export class MapDateRange {
  constructor(controller) {
    this.controller = controller
  }

  /**
   * Convert the server-rendered range to the API format and remember it.
   * Realtime filtering uses the snapshot to tell the default "today" view
   * (whose frozen end goes stale across local midnight) apart from an
   * explicitly selected past range.
   */
  snapshotInitial() {
    const controller = this.controller
    const [serverStartDate, serverEndDate] = [
      controller.startDateValue,
      controller.endDateValue,
    ].map((value) => value.split("T")[0])

    controller.startDateValue = DateManager.formatDateForAPI(
      new Date(controller.startDateValue),
    )
    controller.endDateValue = DateManager.formatDateForAPI(
      new Date(controller.endDateValue),
    )

    const loadEnd = parseTimestamp(controller.endDateValue)
    controller.defaultDateRange = {
      startValue: controller.startDateValue,
      endValue: controller.endDateValue,
      startDate: serverStartDate,
      endDate: serverEndDate,
      reachesNow: loadEnd !== null && loadEnd >= Date.now(),
    }
  }

  /** Month selector changed. The private E2E suite calls it. */
  monthChanged(event) {
    const { startDate, endDate } = DateManager.parseMonthSelector(
      event.target.value,
    )
    return this.setDateRange(startDate, endDate)
  }

  /**
   * Timeline panel requested a new day (SPA navigation — no page reload).
   * Uses the month selector's date format: the Points/Tracks
   * API expects `DateManager.formatDateForAPI`'s local `YYYY-MM-DDTHH:MM+OFFSET`
   * shape. Using `Date#toISOString()` (UTC `Z` suffix) here was causing Tracks
   * to come back empty because the server parsed the dates differently.
   */
  handleTimelineDateNavigated(event) {
    const navigation = this.navigateTimelineDateRange(event.detail || {})
    if (typeof event.detail?.waitUntil === "function") {
      event.detail.waitUntil(navigation)
    } else {
      navigation.catch((error) => console.error(error))
    }
  }

  async navigateTimelineDateRange({
    startAt,
    endAt,
    fitBounds = true,
    timelineLoaded = false,
  }) {
    if (!startAt || !endAt) return

    const toApiDate = (local) => {
      const d = new Date(local)
      if (Number.isNaN(d.getTime())) return null
      return DateManager.formatDateForAPI(d)
    }
    const start = toApiDate(startAt)
    const end = toApiDate(endAt)
    if (!start || !end) return

    await this.setDateRange(start, end, {
      fitBounds,
      refreshTimeline: !timelineLoaded,
    })
  }

  /**
   * The one place the selected range changes: every enabled layer, the
   * Timeline feed and family history reload for it.
   */
  async setDateRange(
    startAt,
    endAt,
    { fitBounds = true, refreshTimeline = true } = {},
  ) {
    const controller = this.controller
    controller.startDateValue = startAt
    controller.endDateValue = endAt

    controller.layerManager.getLayer("map-editor")?.close()
    controller.timelineBridge.clearDayHighlight()
    await controller.loadMapData({ fitBounds })
    if (anomaliesVisible(SettingsManager.getSettings())) {
      controller.layerVisibilityManager.refreshAnomalies({ enabled: true })
    }
    // The Timeline loads its own list when it starts the navigation; a second
    // load would replace that list, and an entry opened in it, a moment later.
    if (refreshTimeline) controller.refreshTimelineFeedIfActive()
    controller.familyManager.debouncedLoadHistory()
  }

  /**
   * The active window realtime points are filtered against. When the range is
   * still the untouched load-time window that reached the present, the end is
   * left open so live points recorded after local midnight keep showing.
   */
  realtimeDateRange() {
    const { startDateValue, endDateValue, defaultDateRange } = this.controller
    const unchanged =
      startDateValue === defaultDateRange?.startValue &&
      endDateValue === defaultDateRange?.endValue

    return {
      startValue: startDateValue,
      endValue: endDateValue,
      treatEndAsOpen: Boolean(unchanged && defaultDateRange?.reachesNow),
    }
  }
}
