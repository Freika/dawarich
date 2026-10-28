# frozen_string_literal: true

module AchievementsHelper
  ACHIEVEMENT_STYLESHEETS = %w[achievements achievements_spectral achievements_unlocks].freeze

  def achievements_visible?
    user_signed_in? && current_user.feature_enabled?(:achievements)
  end

  def achievement_stylesheet_tags
    stylesheet_link_tag(*ACHIEVEMENT_STYLESHEETS, 'data-turbo-track': 'reload')
  end

  def achievement_status_options(set)
    statuses = %w[all unlocked]
    statuses << 'in_progress' if set.level == :country && !set.definition.thematic?
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
    paths = [tag.path(d: silhouette[:path])]
    silhouette.fetch(:colors, []).each do |part|
      paths << tag.path(d: part[:path], fill: part[:color], opacity: '0.65',
                        data: { color: part[:color] }, 'fill-rule': 'evenodd')
    end
    if silhouette[:unvisited_path].present?
      paths << tag.path(d: silhouette[:unvisited_path], class: 'geo-unvisited', data: { unvisited: true })
    end
    tag.svg(
      safe_join(paths),
      viewBox: silhouette[:viewbox],
      preserveAspectRatio: 'xMidYMid meet',
      class: 'ach-silhouette-svg',
      'aria-hidden': true
    )
  end

  def achievement_modal_data
    keys = %i[public_link embed_code iframe_title copy copied share_error copy_error]
    labels = keys.index_with { |key| t("achievements.modal.#{key}") }

    {
      controller: 'card-modal',
      action: 'turbo:before-cache@document->card-modal#prepareForCache',
      card_modal_labels_value: labels.to_json
    }
  end
end
