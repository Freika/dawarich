import { panelPadding } from "../ui/padding.js"

export function createViewportFit(reader, element) {
  let fittedKey
  return async ({ map, config, operation, signal }) => {
    const key = JSON.stringify([config.range, config.epoch])
    if (
      !config.range?.startAt ||
      !config.range?.endAt ||
      !map.fitBounds ||
      key === fittedKey
    )
      return
    let result
    try {
      result = await operation.wait(
        reader.read(
          "bounds",
          {
            start_date: config.range.startAt,
            end_date: config.range.endAt,
            import_id: config.range.importId,
            robust: "true",
          },
          { signal },
        ),
      )
    } catch (error) {
      if (error.name === "AbortError") throw error
      return
    }
    operation.check()
    fittedKey = key
    if (result.status === "no_data") return
    const data = result.data
    const values = [data.min_lng, data.min_lat, data.max_lng, data.max_lat].map(
      Number,
    )
    if (values.some((value) => !Number.isFinite(value))) return
    const [west, south, east, north] = values
    map.fitBounds(
      [
        [west, south],
        [east, north],
      ],
      {
        padding: panelPadding({
          container: map.getContainer?.(),
          notice: () =>
            element?.ownerDocument?.querySelector("#demo-data-banner"),
          overlay: () =>
            element
              ?.closest?.("[data-native-map-root]")
              ?.querySelector("#native-map-panel"),
        })(),
        maxZoom: 15,
        duration: 0,
      },
    )
  }
}
