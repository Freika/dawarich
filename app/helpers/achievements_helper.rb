# frozen_string_literal: true

module AchievementsHelper
  def region_silhouette(silhouette)
    tag.svg(
      tag.path(d: silhouette[:path]),
      viewBox: silhouette[:viewbox],
      preserveAspectRatio: 'xMidYMid meet',
      class: 'ach-silhouette-svg',
      'aria-hidden': true
    )
  end
end
