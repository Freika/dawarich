export function initializeAnalyticsEvents(win = window) {
  const track = (event) => {
    if (typeof win.sa_event === "function") win.sa_event(event.detail.event)
  }
  win.addEventListener("dawarich:track", track)
  return () => win.removeEventListener("dawarich:track", track)
}
