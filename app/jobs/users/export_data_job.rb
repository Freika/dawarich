# frozen_string_literal: true

class Users::ExportDataJob < ApplicationJob
  queue_as :exports

  sidekiq_options retry: false

  def perform(user_id)
    user = find_user_or_skip(user_id) || return

    Users::DataExportLegacy.perform(user, event_id: job_id, zone: Time.zone.name, locale: I18n.locale.to_s)
  end
end
