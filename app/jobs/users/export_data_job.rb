# frozen_string_literal: true

class Users::ExportDataJob < ApplicationJob
  queue_as :exports

  sidekiq_options retry: false

  def perform(user_id)
    user = find_non_deleted_user(user_id)
    return unless user

    Users::ExportData.new(user).export
  end
end
