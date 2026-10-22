import { translate } from "i18n"

export function formatDistance(distance, unit = "km") {
  let smallUnit
  let bigUnit

  if (unit === "mi") {
    distance *= 0.621371
    smallUnit = "ft"
    bigUnit = "mi"

    if (distance < 1) {
      distance *= 5280
      return `${Math.round(distance)} ${smallUnit}`
    }
    return `${distance < 10 ? distance.toFixed(1) : Math.round(distance)} ${bigUnit}`
  }

  smallUnit = "m"
  bigUnit = "km"

  if (distance < 1) {
    distance *= 1000
    return `${Math.round(distance)} ${smallUnit}`
  }
  return `${distance < 10 ? distance.toFixed(1) : Math.round(distance)} ${bigUnit}`
}

export function minutesToDaysHoursMinutes(minutes) {
  const days = Math.floor(minutes / (24 * 60))
  const hours = Math.floor((minutes % (24 * 60)) / 60)
  const remaining = minutes % 60
  let result = ""

  if (days > 0) {
    result += `${translate("time.days_short", { count: days })} `
  }

  if (hours > 0) {
    result += `${translate("time.hours_short", { count: hours })} `
  }

  if (remaining > 0) {
    result += translate("time.minutes_short", { count: remaining })
  }

  return result
}

export function formatSpeed(speedKmh, unit = "km") {
  if (unit === "km") {
    return `${Math.round(speedKmh)} km/h`
  }

  const speedMph = speedKmh * 0.621371
  return `${Math.round(speedMph)} mph`
}
