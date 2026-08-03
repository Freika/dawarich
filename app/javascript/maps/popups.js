import { translate } from "i18n"
import { formatDate } from "./helpers"

export function createPopupContent(marker, timezone, distanceUnit) {
  let speed = marker[5]
  let altitude = marker[3]
  let speedUnit = "km/h"
  let altitudeUnit = "m"

  // convert marker[5] from m/s to km/h first
  speed = speed * 3.6

  if (distanceUnit === "mi") {
    // convert speed from km/h to mph
    speed = speed * 0.621371
    speedUnit = "mph"
    // convert altitude from meters to feet
    altitude = altitude * 3.28084
    altitudeUnit = "ft"
  }

  speed = Math.round(speed)
  altitude = Math.round(altitude)

  return `
    <strong>${translate("map_info.timestamp")}:</strong> ${formatDate(marker[4], timezone)}<br>
    <strong>${translate("map_info.latitude")}:</strong> ${marker[0]}<br>
    <strong>${translate("map_info.longitude")}:</strong> ${marker[1]}<br>
    <strong>${translate("map_info.altitude")}:</strong> ${altitude}${altitudeUnit}<br>
    <strong>${translate("map_info.speed")}:</strong> ${speed}${speedUnit}<br>
    <strong>${translate("map_info.battery")}:</strong> ${marker[2]}%<br>
    <strong>${translate("map_info.id")}:</strong> ${marker[6]}<br>
    <a href="#" data-id="${marker[6]}" class="delete-point">[${translate("common.delete")}]</a>
  `
}
