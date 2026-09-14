# frozen_string_literal: true

module AchievementsHelper
  def achievement_status_options(set)
    statuses = %w[all unlocked]
    statuses << 'in_progress' if set.level == :country
    statuses << 'locked'
    statuses.map { |status| [t("achievements.ui.status.#{status}"), status] }
  end

  def achievement_page_range(cards)
    first = cards.empty? ? 0 : cards.offset_value + 1
    last = cards.empty? ? 0 : cards.offset_value + cards.length
    t('achievements.ui.page_range', first: first, last: last,
                                    total: number_with_delimiter(cards.total_count))
  end

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
