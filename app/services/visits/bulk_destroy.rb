# frozen_string_literal: true

module Visits
  class BulkDestroy
    MAX_VISIT_IDS = 500
    POINT_NULLIFY_BATCH = 50

    attr_reader :user, :visit_ids, :errors

    def initialize(user, visit_ids)
      @user = user
      @visit_ids = visit_ids
      @errors = []
    end

    def call
      validate
      return false if errors.any?

      destroy_visits
    end

    private

    def validate
      return errors << I18n.t('services.visits.bulk_destroy.none_selected') if visit_ids.blank?
      return if visit_ids.length <= MAX_VISIT_IDS

      errors << I18n.t('services.visits.bulk_destroy.too_many_selected', max: MAX_VISIT_IDS)
    end

    def destroy_visits
      visits = user.scoped_visits.where(id: visit_ids).order(:id)
      ids = visits.pluck(:id)

      if ids.empty?
        errors << I18n.t('services.visits.bulk_destroy.none_found')
        return false
      end

      started_ats = visits.pluck(:started_at)
      started_at = Time.current

      ids.each_slice(POINT_NULLIFY_BATCH) do |chunk|
        Visit.transaction do
          Point.where(visit_id: chunk).update_all(visit_id: nil)
          PlaceVisit.where(visit_id: chunk).delete_all
          Visit.where(id: chunk).delete_all
        end
      end

      log_success(ids.length, Time.current - started_at)

      { count: ids.length, started_ats: started_ats }
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.warn(
        "Visits::BulkDestroy failed user_id=#{user.id} count=#{ids&.length} error=#{e.class}: #{e.message}"
      )
      errors << I18n.t('services.visits.bulk_destroy.database_error')
      false
    end

    def log_success(count, duration_seconds)
      Rails.logger.info(
        "Visits::BulkDestroy user_id=#{user.id} count=#{count} duration_ms=#{(duration_seconds * 1000).round}"
      )
    end
  end
end
