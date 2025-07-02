# frozen_string_literal: true

class Users::ExportDataJob < ApplicationJob
  queue_as :exports

  sidekiq_options retry: false

  def perform(user_id)
    user = User.find(user_id)

    Users::ExportData.new(user).export
  end
end
