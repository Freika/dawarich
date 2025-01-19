import { formatDate } from "./helpers";

export function createPopupContent(marker, timezone, distanceUnit) {
  if (distanceUnit === "mi") {
    // convert marker[5] from km/h to mph
    marker[5] = marker[5] * 0.621371;
    // convert marker[3] from meters to feet
    marker[3] = marker[3] * 3.28084;
  }

  // convert marker[5] from m/s to km/h and round to nearest integer
  marker[5] = Math.round(marker[5] * 3.6);

  return `
    <strong>Timestamp:</strong> ${formatDate(marker[4], timezone)}<br>
    <strong>Latitude:</strong> ${marker[0]}<br>
    <strong>Longitude:</strong> ${marker[1]}<br>
    <strong>Altitude:</strong> ${marker[3]}m<br>
    <strong>Speed:</strong> ${marker[5]}km/h<br>
    <strong>Battery:</strong> ${marker[2]}%<br>
    <strong>Id:</strong> ${marker[6]}<br>
    <a href="#" data-id="${marker[6]}" class="delete-point">[Delete]</a>
  `;
}
