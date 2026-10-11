export function rememberMapState(hook) {
  hook.mapOwnedState = hook.el.dataset.mapState
}

export function restoreMapState(hook) {
  const state = hook.mapOwner?.presentationState ?? hook.mapOwnedState
  if (state) hook.el.dataset.mapState = state
}
