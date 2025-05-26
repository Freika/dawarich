import { formatDate } from "./helpers";

export function createPopupContent(marker, timezone, distanceUnit) {
  let speed = marker[5];
  let altitude = marker[3];
  let speedUnit = 'km/h';
  let altitudeUnit = 'm';

  // convert marker[5] from m/s to km/h first
  speed = speed * 3.6;

  if (distanceUnit === "mi") {
    // convert speed from km/h to mph
    speed = speed * 0.621371;
    speedUnit = 'mph';
    // convert altitude from meters to feet
    altitude = altitude * 3.28084;
    altitudeUnit = 'ft';
  }

  speed = Math.round(speed);
  altitude = Math.round(altitude);

  return `
    <strong>Timestamp:</strong> ${formatDate(marker[4], timezone)}<br>
    <strong>Latitude:</strong> ${marker[0]}<br>
    <strong>Longitude:</strong> ${marker[1]}<br>
    <strong>Altitude:</strong> ${altitude}${altitudeUnit}<br>
    <strong>Speed:</strong> ${speed}${speedUnit}<br>
    <strong>Battery:</strong> ${marker[2]}%<br>
    <strong>Id:</strong> ${marker[6]}<br>
    <a href="#" data-id="${marker[6]}" class="delete-point">[Delete]</a>
  `;
}
