// javascript/maps/helpers.js
export function formatDistance(distance, unit = 'km') {
  let smallUnit, bigUnit;

  if (unit === 'mi') {
    distance *= 0.621371; // Convert km to miles
    smallUnit = 'ft';
    bigUnit = 'mi';

    // If the distance is less than 1 mile, return it in feet
    if (distance < 1) {
      distance *= 5280; // Convert miles to feet
      return `${distance.toFixed(2)} ${smallUnit}`;
    } else {
      return `${distance.toFixed(2)} ${bigUnit}`;
    }
  } else {
    smallUnit = 'm';
    bigUnit = 'km';

    // If the distance is less than 1 km, return it in meters
    if (distance < 1) {
      distance *= 1000; // Convert km to meters
      return `${distance.toFixed(2)} ${smallUnit}`;
    } else {
      return `${distance.toFixed(2)} ${bigUnit}`;
    }
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
  let date;

  // Handle different timestamp formats
  if (typeof timestamp === 'number') {
    // Unix timestamp in seconds, convert to milliseconds
    date = new Date(timestamp * 1000);
  } else if (typeof timestamp === 'string') {
    // Check if string is a numeric timestamp
    if (/^\d+$/.test(timestamp)) {
      // String representation of Unix timestamp in seconds
      date = new Date(parseInt(timestamp) * 1000);
    } else {
      // Assume it's an ISO8601 string, parse directly
      date = new Date(timestamp);
    }
  } else {
    // Invalid input
    return 'Invalid Date';
  }

  // Check if date is valid
  if (isNaN(date.getTime())) {
    return 'Invalid Date';
  }

  let locale;
  if (navigator.languages !== undefined) {
    locale = navigator.languages[0];
  } else if (navigator.language) {
    locale = navigator.language;
  } else {
    locale = 'en-GB';
  }
  return date.toLocaleString(locale, { timeZone: timezone });
}

export function formatSpeed(speedKmh, unit = 'km') {
  if (unit === 'km') {
    return `${Math.round(speedKmh)} km/h`;
  } else {
    const speedMph = speedKmh * 0.621371; // Convert km/h to mph
    return `${Math.round(speedMph)} mph`;
  }
}

export function haversineDistance(lat1, lon1, lat2, lon2, unit = 'km') {
  // Haversine formula to calculate the distance between two points
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

export function showFlashMessage(type, message) {
  // Get or create the flash container
  let flashContainer = document.getElementById('flash-messages');
  if (!flashContainer) {
    flashContainer = document.createElement('div');
    flashContainer.id = 'flash-messages';
    flashContainer.className = 'fixed top-5 right-5 flex flex-col-reverse gap-2 z-50';
    document.body.appendChild(flashContainer);
  }

  // Create the flash message div
  const flashDiv = document.createElement('div');
  flashDiv.setAttribute('data-controller', 'removals');
  flashDiv.className = `flex items-center justify-between ${classesForFlash(type)} py-3 px-5 rounded-lg z-50`;

  // Create the message div
  const messageDiv = document.createElement('div');
  messageDiv.className = 'mr-4';
  messageDiv.innerText = message;

  // Create the close button
  const closeButton = document.createElement('button');
  closeButton.setAttribute('type', 'button');
  closeButton.setAttribute('data-action', 'click->removals#remove');
  closeButton.className = 'ml-auto'; // Ensures button stays on the right

  // Create the SVG icon for the close button
  const closeIcon = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  closeIcon.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
  closeIcon.setAttribute('class', 'h-6 w-6');
  closeIcon.setAttribute('fill', 'none');
  closeIcon.setAttribute('viewBox', '0 0 24 24');
  closeIcon.setAttribute('stroke', 'currentColor');

  const closeIconPath = document.createElementNS('http://www.w3.org/2000/svg', 'path');
  closeIconPath.setAttribute('stroke-linecap', 'round');
  closeIconPath.setAttribute('stroke-linejoin', 'round');
  closeIconPath.setAttribute('stroke-width', '2');
  closeIconPath.setAttribute('d', 'M6 18L18 6M6 6l12 12');

  // Append all elements
  closeIcon.appendChild(closeIconPath);
  closeButton.appendChild(closeIcon);
  flashDiv.appendChild(messageDiv);
  flashDiv.appendChild(closeButton);
  flashContainer.appendChild(flashDiv);

  // Automatically remove after 5 seconds
  setTimeout(() => {
    if (flashDiv && flashDiv.parentNode) {
      flashDiv.remove();
      // Remove container if empty
      if (flashContainer && !flashContainer.hasChildNodes()) {
        flashContainer.remove();
      }
    }
  }, 5000);
}

function classesForFlash(type) {
  switch (type) {
    case 'error':
      return 'bg-red-100 text-red-700 border-red-300';
    case 'notice':
      return 'bg-blue-100 text-blue-700 border-blue-300';
    default:
      return 'bg-blue-100 text-blue-700 border-blue-300';
  }
}

export function debounce(func, wait) {
  let timeout;
  return function executedFunction(...args) {
    const later = () => {
      clearTimeout(timeout);
      func(...args);
    };
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
  };
}