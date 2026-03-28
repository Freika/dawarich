# frozen_string_literal: true

class Users::ResetPointsCounterJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    DataMigrations::PrefillPointsCounterCacheJob.new.perform(user_id)
  end
end
