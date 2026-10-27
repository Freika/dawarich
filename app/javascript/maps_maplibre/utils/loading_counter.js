export class LoadingCounter {
  constructor(onUpdate) {
    this.onUpdate = onUpdate
    this.counts = {}
    this.completed = new Set()
    this.expectedSources = new Set()
  }

  expect(source) {
    this.expectedSources.add(source)
    this._report()
  }

  update(source, count) {
    this.counts[source] = count
    this._report()
  }

  complete(source) {
    this.completed.add(source)
    this._report()
  }

  isComplete() {
    return (
      this.expectedSources.size > 0 &&
      [...this.expectedSources].every((s) => this.completed.has(s))
    )
  }

  _report() {
    if (!this.onUpdate) return
    const fullCounts = {}
    for (const source of this.expectedSources) {
      fullCounts[source] = this.counts[source] || 0
    }
    this.onUpdate({
      counts: fullCounts,
      isComplete: this.isComplete(),
    })
  }
}
