// Quote-safe HTML escaping for values interpolated into markup.
//
// A text-node round-trip (div.textContent -> div.innerHTML) escapes only
// & < >, leaving " and ' intact. That is unsafe inside a quoted attribute: a
// value can close the attribute and inject a new one (e.g. an event handler).
// This helper escapes all five so the same function is safe in both element
// and attribute contexts.

const ENTITIES = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
}

/** Escape a value for safe interpolation into element or attribute HTML. */
export function escapeHtml(value) {
  if (value == null) return ""
  return String(value).replace(/[&<>"']/g, (char) => ENTITIES[char])
}
