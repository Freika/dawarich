# frozen_string_literal: true

module Achievements
  class MigrateExplorationState
    RENAMES = {
      'explorer_germany' => 'country_de',
      'explorer_usa' => 'country_us',
      'explorer_europe' => 'continent_europe'
    }.freeze

    LEGACY_KEYS = (RENAMES.keys + %w[border_hopper globetrotter world_traveler]).freeze

    def call
      ActiveRecord::Base.transaction do
        legacy_rows.group_by(&:user_id).each { |user_id, rows| merge_user(user_id, rows) }
        rename_awards
      end
    end

    private

    def legacy_rows
      Progress.where(achievement_key: LEGACY_KEYS).to_a
    end

    def merge_user(user_id, rows)
      earned = merge_earned(rows)
      store_exploration(user_id, earned)

      carriers, disposable = rows.partition { |row| carrier?(row) }
      Progress.where(id: disposable.map(&:id)).delete_all

      carriers.each do |row|
        row.update!(achievement_key: RENAMES.fetch(row.achievement_key, row.achievement_key), state: {})
      end
    end

    def merge_earned(rows)
      rows.each_with_object({}) do |row, merged|
        row.state.fetch('earned', {}).each do |code, earned_at|
          merged[code] = earned_at if merged[code].nil? || earned_at < merged[code]
        end
      end
    end

    def store_exploration(user_id, earned)
      exploration = Progress.find_or_initialize_by(user_id: user_id, achievement_key: Progress::EXPLORATION_KEY)
      previous = exploration.state.fetch('earned', {})

      exploration.state = { 'earned' => previous.merge(earned) { |_code, a, b| [a, b].min },
                            'dwell' => {}, 'cursor' => 0 }
      exploration.save!
    end

    def carrier?(row)
      row.sharing_enabled? || row.sharing_uuid.present?
    end

    def rename_awards
      RENAMES.each do |old_key, new_key|
        UserAchievement.where(achievement_key: old_key).find_each do |award|
          taken = UserAchievement.exists?(user_id: award.user_id, achievement_key: new_key)
          taken ? award.destroy! : award.update!(achievement_key: new_key)
        end
      end
    end
  end
end
