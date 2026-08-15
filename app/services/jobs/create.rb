# frozen_string_literal: true

class Jobs::Create
  BULK_ENQUEUE_BATCH_SIZE = 1_000

  class InvalidJobName < StandardError; end
  class PaidProviderForceRerunBlocked < StandardError; end

  attr_reader :job_name, :user

  def initialize(job_name, user_id)
    @job_name = job_name
    @user = User.find(user_id)
  end

  def call
    case job_name
    when 'start_reverse_geocoding'
      guard_paid_provider_force_rerun!
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
      ids = batch.pluck(:id)
      ids = force ? clear_dedup_keys(ids) : claim_dedup_keys(ids)
      next if ids.empty?

      jobs = ids.map { |id| ReverseGeocodingJob.new('Point', id, force: force) }
      begin
        ActiveJob.perform_all_later(jobs)
      rescue StandardError
        clear_dedup_keys(ids) unless force
        raise
      end
    end
  end

  def claim_dedup_keys(ids)
    results = Sidekiq.redis do |redis|
      redis.pipelined do |pipe|
        ids.each do |id|
          pipe.set(Point.geocode_dedup_key(id), 1, nx: true, ex: Point::GEOCODE_DEDUP_TTL)
        end
      end
    end
    ids.zip(results).filter_map { |id, claimed| id if claimed }
  end

  def clear_dedup_keys(ids)
    Sidekiq.redis do |redis|
      redis.pipelined do |pipe|
        ids.each { |id| pipe.del(Point.geocode_dedup_key(id)) }
      end
    end
    ids
  end

  # Cloud users share the operator's geocoding budget, so a click that
  # force-reruns reverse geocoding on a paid provider could fan out to
  # millions of paid lookups. Self-hosted users own their provider key and
  # bill — they keep the override.
  def guard_paid_provider_force_rerun!
    return unless paid_provider?
    return if DawarichSettings.self_hosted?

    point_count = user.points.size
    Rails.logger.warn(
      "[Jobs::Create] Refusing to force-rerun reverse geocoding for user=#{user.id} " \
      "with #{point_count} points: a paid provider (#{paid_provider_name}) is configured " \
      'on a non-self-hosted instance.'
    )

    raise PaidProviderForceRerunBlocked,
          'Force re-run is not available for paid geocoding providers on hosted instances.'
  end

  def paid_provider?
    DawarichSettings.geoapify_enabled? || DawarichSettings.locationiq_enabled?
  end

  def paid_provider_name
    return 'locationiq' if DawarichSettings.locationiq_enabled?
    return 'geoapify' if DawarichSettings.geoapify_enabled?

    'unknown'
  end
end
