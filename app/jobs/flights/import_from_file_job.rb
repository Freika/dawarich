# frozen_string_literal: true

module Flights
  class ImportFromFileJob < ApplicationJob
    queue_as :imports

    def perform(user_id, blob_id, format = nil)
      blob = ActiveStorage::Blob.find_by(id: blob_id)
      return if blob.blank?

      user = find_user_or_skip(user_id)
      return if user.blank?

      counts = Flights::ImportFromFile.new(user, blob.download, format: format).call
      notify_import_succeeded(user, counts)
    rescue Flights::Parsers::Error => e
      ExceptionReporter.call(e, "Flight file import failed for user #{user_id}")
      notify_import_failed(user, e)
    ensure
      blob&.purge
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
