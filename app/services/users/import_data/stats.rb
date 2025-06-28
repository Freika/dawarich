# frozen_string_literal: true

class Users::ImportData::Stats
  def initialize(user, stats_data)
    @user = user
    @stats_data = stats_data
  end

  def call
    return 0 unless stats_data.is_a?(Array)

    Rails.logger.info "Importing #{stats_data.size} stats for user: #{user.email}"

    stats_created = 0

    stats_data.each do |stat_data|
      next unless stat_data.is_a?(Hash)

      # Check if stat already exists (match by year and month)
      existing_stat = user.stats.find_by(
        year: stat_data['year'],
        month: stat_data['month']
      )

      if existing_stat
        Rails.logger.debug "Stat already exists: #{stat_data['year']}-#{stat_data['month']}"
        next
      end

      # Create new stat
      stat_attributes = stat_data.except('created_at', 'updated_at')
      stat = user.stats.create!(stat_attributes)
      stats_created += 1

      Rails.logger.debug "Created stat: #{stat.year}-#{stat.month}"
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Failed to create stat: #{e.message}"
      next
    end

    Rails.logger.info "Stats import completed. Created: #{stats_created}"
    stats_created
  end

  private

  attr_reader :user, :stats_data
end
