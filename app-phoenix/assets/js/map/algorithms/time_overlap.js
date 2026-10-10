export function timeOverlapOpacityExpr(
  startProperty,
  endProperty,
  rangeStart,
  rangeEnd,
  fullOpacity,
  dimOpacity,
) {
  return [
    "case",
    [
      "all",
      ["has", startProperty],
      ["has", endProperty],
      ["<=", ["get", startProperty], rangeEnd],
      [">=", ["get", endProperty], rangeStart],
    ],
    fullOpacity,
    dimOpacity,
  ]
}
