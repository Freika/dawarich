# frozen_string_literal: true

class Families::ExpireLocationRequestsJob < ApplicationJob
  queue_as :families

  OWNERSHIP_KEY = 'cron:family_location_requests_expiry_job'

  def perform
    JobOwnership.with_owner(OWNERSHIP_KEY) do
      Family::LocationRequest
        .pending
        .where('expires_at <= ?', Time.current)
        .update_all(status: Family::LocationRequest.statuses[:expired], updated_at: Time.current)
    end
  end
end
