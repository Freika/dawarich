export function launchRequestedStudio(studio, provider, options = {}) {
  const query = options.query ?? window.location.search
  if (new URLSearchParams(query).get("studio") !== "video") return () => {}
  let active = true
  let observer
  const stop = () => {
    active = false
    observer?.disconnect()
  }
  const launch = () => {
    if (
      !active ||
      !provider.controller?.map ||
      !provider.controller?.mapDataManager
    )
      return
    stop()
    studio.open(provider)
  }
  const Observer = options.Observer ?? MutationObserver
  observer = new Observer(launch)
  observer.observe(options.root ?? document.body, {
    childList: true,
    subtree: true,
    attributes: true,
  })
  launch()
  return stop
}
