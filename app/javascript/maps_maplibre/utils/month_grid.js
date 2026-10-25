export function monthGridStart(year, monthIndex, firstDayOfWeek) {
  const offset =
    (new Date(year, monthIndex, 1).getDay() - firstDayOfWeek + 7) % 7
  return new Date(year, monthIndex, 1 - offset)
}
