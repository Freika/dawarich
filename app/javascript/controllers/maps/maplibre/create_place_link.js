export function consumeCreatePlaceLink(
  manager,
  location = window.location,
  history = window.history,
) {
  const url = new URL(location.href)
  if (url.searchParams.get("create_place") !== "1") return

  manager.startCreatePlace()
  url.searchParams.delete("create_place")
  history.replaceState(history.state, "", url.toString())
}
