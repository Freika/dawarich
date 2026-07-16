# frozen_string_literal: true

module Flights
  class ImportFromFileJob < ApplicationJob
    queue_as :imports

    def perform(user_id, content, format = nil)
      user = find_user_or_skip(user_id) || return

      counts = Flights::ImportFromFile.new(user, content, format: format).call
      notify_import_succeeded(user, counts)
    rescue Flights::Parsers::Error => e
      ExceptionReporter.call(e, "Flight file import failed for user #{user_id}")
      notify_import_failed(user, e)
      raise e
    end

    private

    def notify_import_succeeded(user, counts)
      Notifications::Create.new(
        user: user,
        title: 'Flight import completed',
        content: "Imported flights from file: #{counts[:created]} created, #{counts[:updated]} updated.",
        kind: :info
      ).call
    end

    def notify_import_failed(user, error)
      return if user.blank?

      Notifications::Create.new(
        user: user,
        title: 'Flight import failed',
        content: "Your flight file import failed: #{error.message}",
        kind: :error
      ).call
    end
  end
end
