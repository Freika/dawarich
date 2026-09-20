# frozen_string_literal: true

module Visits
  class BulkDestroy
    MAX_VISIT_IDS = 500

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
      place_ids = visits.reorder(nil).where.not(place_id: nil).distinct.pluck(:place_id)
      started_at = Time.current

      # Soft delete: rows stay as tombstones (points and place links intact)
      # so visit detection never re-suggests what the user removed.
      Visit.where(id: ids).update_all(deleted_at: Time.current)

      # update_all skips AR callbacks, so the orphan-place check the model
      # runs on single soft deletes must be enqueued here by hand.
      place_ids.each { |place_id| Places::DeleteIfOrphanJob.perform_later(place_id) }

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
