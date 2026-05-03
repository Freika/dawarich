# frozen_string_literal: true

class Jobs::Create
  class InvalidJobName < StandardError; end

  attr_reader :job_name, :user

  def initialize(job_name, user_id)
    @job_name = job_name
    @user = User.find(user_id)
  end

  BULK_ENQUEUE_BATCH_SIZE = 1_000

  def call
    case job_name
    when 'start_reverse_geocoding'
      bulk_enqueue(user.points, force: true)
    when 'continue_reverse_geocoding'
      bulk_enqueue(user.points.not_reverse_geocoded, force: false)
    else
      raise InvalidJobName, 'Invalid job name'
    end
  end

  private

  def bulk_enqueue(points_relation, force:)
    return unless DawarichSettings.reverse_geocoding_enabled?

    points_relation.in_batches(of: BULK_ENQUEUE_BATCH_SIZE) do |batch|
      jobs = batch.pluck(:id).map { |id| ReverseGeocodingJob.new('Point', id, force: force) }
      ActiveJob.perform_all_later(jobs)
    end
  end
end
