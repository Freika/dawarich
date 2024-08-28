// javascript/maps/helpers.js
export function formatDistance(distance, unit = 'km') {
  if (unit === 'mi') {
    distance *= 0.621371; // Convert to miles
    var smallUnit = 'ft';
    var bigUnit = 'mi';

    // If the distance is less than 1 mi, return it in feet
    // else return it in miles
    if (distance < 621) {
      distance *= 5280;

      return `${distance.toFixed(2)} ${smallUnit}`;
    }
  } else {
    var smallUnit = 'm';
    var bigUnit = 'km';
  }

  // If the distance is less than 1 km/mi, return it in meters/feet

  if (distance < 1000) {
    return `${distance.toFixed(2)} ${smallUnit}`;
  } else {
    return `${(distance / 1000).toFixed(2)} ${bigUnit}`;
  }
}

export function getUrlParameter(name) {
  return new URLSearchParams(window.location.search).get(name);
}

export function minutesToDaysHoursMinutes(minutes) {
  const days = Math.floor(minutes / (24 * 60));
  const hours = Math.floor((minutes % (24 * 60)) / 60);
  minutes = minutes % 60;
  let result = "";

  if (days > 0) {
    result += `${days}d `;
  }

  if (hours > 0) {
    result += `${hours}h `;
  }

  if (minutes > 0) {
    result += `${minutes}min`;
  }

  return result;
}

export function formatDate(timestamp, timezone) {
  const date = new Date(timestamp * 1000);
  return date.toLocaleString("en-GB", { timeZone: timezone });
}

export function haversineDistance(lat1, lon1, lat2, lon2, unit = 'km') {
  const toRad = (x) => (x * Math.PI) / 180;
  const R_km = 6371; // Radius of the Earth in kilometers
  const R_miles = 3959; // Radius of the Earth in miles
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  if (unit === 'miles') {
    return R_miles * c; // Distance in miles
  } else {
    return R_km * c; // Distance in kilometers
  }
}
