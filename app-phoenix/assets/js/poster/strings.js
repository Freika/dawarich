export const interpolate = (text, values = {}) =>
  (text ?? "").replace(/%\{(\w+)\}/g, (match, name) => values[name] ?? match)
