# frozen_string_literal: true

class DataMigrations::DedupeTracksForUniqueIndexJob < ApplicationJob
  queue_as :data_migrations

  def perform
    user_ids = users_with_duplicates
    return if user_ids.empty?

    Rails.logger.info "[DataMigrations::DedupeTracksForUniqueIndex] Deduplicating tracks for #{user_ids.size} user(s)"

    user_ids.each do |user_id|
      user = User.find_by(id: user_id)
      next unless user

      removed = Tracks::Deduplicator.new(user).call
      next if removed.zero?

      Rails.logger.info(
        "[DataMigrations::DedupeTracksForUniqueIndex] user_id=#{user_id} removed=#{removed} duplicate track(s)"
      )
    end
  end

  private

  def users_with_duplicates
    sql = <<~SQL.squish
      SELECT DISTINCT user_id FROM tracks
      WHERE (user_id, start_at, end_at) IN (
        SELECT user_id, start_at, end_at FROM tracks
        GROUP BY user_id, start_at, end_at
        HAVING COUNT(*) > 1
      )
    SQL
    ActiveRecord::Base.connection.execute(sql).map { |row| row['user_id'].to_i }
  end
end
