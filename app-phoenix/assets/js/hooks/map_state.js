export function rememberMapState(hook) {
  hook.mapOwnedState = hook.el.dataset.mapState
}

export function restoreMapState(hook) {
  if (hook.mapOwnedState) hook.el.dataset.mapState = hook.mapOwnedState
}
