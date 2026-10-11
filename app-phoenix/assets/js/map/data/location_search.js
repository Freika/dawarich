export function createLocationSearch({ reader, minLength = 2 }) {
  let generation = 0
  let controller = null

  function cancel() {
    generation++
    controller?.abort()
    controller = null
  }

  async function suggest(query) {
    cancel()
    const text = String(query || "").trim()
    if (text.length < minLength) return { status: "ok", suggestions: [] }
    const current = generation
    controller = new AbortController()
    try {
      const { data } = await reader.read(
        "suggestions",
        { q: text },
        { signal: controller.signal },
      )
      if (current !== generation) return { status: "stale" }
      return {
        status: "ok",
        suggestions: (data?.suggestions || []).map((item) => ({
          name: item.name,
          address: item.address,
          lat: item.coordinates?.[0],
          lon: item.coordinates?.[1],
          type: item.type,
        })),
      }
    } catch (error) {
      if (current !== generation || error.name === "AbortError")
        return { status: "stale" }
      return { status: "error" }
    }
  }

  async function visits({ lat, lon, name, address = "" }, { signal } = {}) {
    const { data } = await reader.read(
      "locations",
      { lat: String(lat), lon: String(lon), name, address },
      { signal },
    )
    return data
  }

  return { suggest, visits, cancel }
}
