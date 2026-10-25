export function setButtonActive(button, active) {
  if (!button) return
  if (active) {
    button.classList.remove("btn-outline")
    button.classList.add("btn-active", "btn-primary")
  } else {
    button.classList.remove("btn-active", "btn-primary")
    button.classList.add("btn-outline")
  }
}
