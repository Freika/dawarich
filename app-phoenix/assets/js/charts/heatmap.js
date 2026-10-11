export const NativeHeatmap = {
  mounted() {
    this.updated()
  },
  updated() {
    const target = this.el.querySelector(
      `[data-date="${this.el.dataset.activityHeatmapTargetDateValue}"]`,
    )
    const scroller = target?.closest(".overflow-x-auto")
    if (scroller)
      scroller.scrollLeft = target.offsetLeft - scroller.clientWidth / 2
  },
}
