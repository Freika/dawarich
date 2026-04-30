# frozen_string_literal: true

class Families::ExpireLocationRequestsJob < ApplicationJob
  queue_as :families

  def perform
    Family::LocationRequest
      .pending
      .where('expires_at <= ?', Time.current)
      .update_all(status: Family::LocationRequest.statuses[:expired], updated_at: Time.current)
  end
end
