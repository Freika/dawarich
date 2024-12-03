# frozen_string_literal: true

class EnqueueBackgroundJob < ApplicationJob
  queue_as :reverse_geocoding

  def perform(job_name, user_id)
    case job_name
    when 'start_immich_import'
      Import::ImmichGeodataJob.perform_later(user_id)
    when 'start_photoprism_import'
      Import::PhotoprismGeodataJob.perform_later(user_id)
    when 'start_reverse_geocoding', 'continue_reverse_geocoding'
      Jobs::Create.new(job_name, user_id).call
    else
      raise ArgumentError, "Unknown job name: #{job_name}"
    end
  end
end
