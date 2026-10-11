export function createScrubber({ input, onMinute }) {
  const onInput = () => onMinute(Number.parseInt(input.value, 10))
  input.addEventListener("input", onInput)

  return {
    setRange(lengthMinutes) {
      input.max = String(Math.max(lengthMinutes - 1, 0))
    },
    set(minute) {
      input.value = String(minute)
    },
    destroy() {
      input.removeEventListener("input", onInput)
    },
  }
}
