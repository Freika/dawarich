# frozen_string_literal: true

class Stats::BackfillTimezoneRebucketJob < ApplicationJob
  include Resumable

  queue_as :stats

  JITTER_WINDOW = 2.hours
  BATCH_SIZE = 1000

  def perform(batch_size: BATCH_SIZE)
    step :rebucket, start: 0 do |step|
      loop do
        rows = Stat.where('id > ?', step.cursor)
                   .order(:id)
                   .limit(batch_size)
                   .pluck(:id, :user_id, :year, :month)

        break if rows.empty?

        rows.each do |_id, user_id, year, month|
          Stats::CalculatingJob
            .set(wait: rand(0..JITTER_WINDOW.to_i).seconds)
            .perform_later(user_id, year, month)
        end

        step.set!(rows.last.first)
      end
    end
  end
end
