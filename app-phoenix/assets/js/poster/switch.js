export function bindStudioSwitch({
  find,
  on,
  studio,
  source,
  openVideo,
  close,
}) {
  const button = find("switch-video")
  if (!button) return
  button.hidden = !openVideo
  on(button, "click", () => {
    if (!openVideo || studio.state.rangeLoading) return
    close()
    openVideo(source)
  })
}
