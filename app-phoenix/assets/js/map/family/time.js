export const familyLastSeen = (location, labels, now = Date.now()) => {
  const { words, ago, middot } = labels
  const minutes = Math.round(Math.abs(now / 1000 - location.timestamp) / 60)
  const buckets = [
    [1, "less_than_x_minutes", 1],
    [45, "x_minutes", minutes],
    [90, "about_x_hours", 1],
    [1440, "about_x_hours", Math.round(minutes / 60)],
    [2520, "x_days", 1],
    [43200, "x_days", Math.round(minutes / 1440)],
    [86400, "about_x_months", Math.round(minutes / 43200)],
    [525600, "x_months", Math.round(minutes / 43200)],
  ]
  let bucket = buckets.find(([limit]) => minutes < limit)
  if (!bucket) {
    const dates = [new Date(location.timestamp * 1000), new Date(now)].sort(
      (a, b) => a - b,
    )
    const from =
      dates[0].getUTCFullYear() + (dates[0].getUTCMonth() >= 2 ? 1 : 0)
    const to = dates[1].getUTCFullYear() - (dates[1].getUTCMonth() < 2 ? 1 : 0)
    const leaps = (year) =>
      Math.floor(year / 4) - Math.floor(year / 100) + Math.floor(year / 400)
    const offset =
      minutes - (from > to ? 0 : leaps(to) - leaps(from - 1)) * 1440
    const remainder = offset % 525600
    const years = Math.floor(offset / 525600)
    bucket = [
      Infinity,
      remainder < 131400
        ? "about_x_years"
        : remainder < 394200
          ? "over_x_years"
          : "almost_x_years",
      years + (remainder >= 394200 ? 1 : 0),
    ]
  }
  const [, key, count] = bucket
  const word =
    typeof words[key] === "string"
      ? words[key]
      : words[key][count === 1 ? "one" : "other"]
  return `${middot} ${ago.replace("%{time}", word.replace("%{count}", count))}`
}
