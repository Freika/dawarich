import { cancelled, createRequestScope } from "./request_scope.js"

export function createStudioSource({
  getState,
  readSnapshot,
  applyDates,
  fixedRange = false,
}) {
  const operations = createRequestScope()

  async function snapshot({ purpose, signal } = {}) {
    if (!["poster", "video", "replay"].includes(purpose))
      throw new Error("Unknown snapshot purpose")
    const operation = operations.begin(signal)
    const state = getState()
    try {
      const data = await operation.wait(
        readSnapshot(state, { purpose, signal: operation.signal }),
      )
      operation.check()
      if (state.revision !== getState().revision) throw cancelled()
      return {
        ...data,
        revision: state.revision,
        range: { ...state.range },
        title: state.title,
      }
    } finally {
      operation.close()
    }
  }

  async function changeDates(range, { signal } = {}) {
    if (fixedRange) throw new Error("Trip range is fixed")
    if (!applyDates) throw new Error("Range change unavailable")
    operations.reset()
    const operation = operations.begin(signal)
    try {
      const receipt = await operation.wait(
        applyDates(range, { signal: operation.signal }),
      )
      operation.check()
      if (receipt.revision !== getState().revision) throw cancelled()
      return receipt
    } finally {
      operation.close()
    }
  }

  return {
    snapshot,
    applyDates: changeDates,
    reset: () => operations.reset(),
    destroy: () => operations.destroy(),
    fixedRange,
  }
}
