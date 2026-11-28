export function anomaliesVisible(settings) {
  return (
    settings?.anomaliesEnabled === true && settings?.pointsVisible !== false
  )
}
