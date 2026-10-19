export function installDayFit({ owner, lifetime }) {
  owner.fitDay = (bounds) => {
    const { sw_lng, sw_lat, ne_lng, ne_lat } = bounds || {}
    if (![sw_lng, sw_lat, ne_lng, ne_lat].every(Number.isFinite)) return
    owner.map?.fitBounds(
      [
        [sw_lng, sw_lat],
        [ne_lng, ne_lat],
      ],
      { padding: 60, duration: 500 },
    )
  }
  lifetime.own(() => delete owner.fitDay)
}
