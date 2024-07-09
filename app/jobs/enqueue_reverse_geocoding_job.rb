# frozen_string_literal: true

class EnqueueReverseGeocodingJob < ApplicationJob
  queue_as :reverse_geocoding

  def perform(job_name, user_id)
    Jobs::Create.new(job_name, user_id).call
  end
end
