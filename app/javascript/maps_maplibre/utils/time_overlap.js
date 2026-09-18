/** Keep a tile feature bright when any part of its time span overlaps the range. */
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
