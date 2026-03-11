# frozen_string_literal: true

class Users::ExportDataJob < ApplicationJob
  queue_as :exports

  sidekiq_options retry: false

  def perform(user_id)
    user = find_user_or_skip(user_id) || return

    Users::ExportData.new(user).export
  end
end
