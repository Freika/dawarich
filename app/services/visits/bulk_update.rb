# frozen_string_literal: true

module Visits
  class BulkUpdate
    attr_reader :user, :visit_ids, :status, :errors

    def initialize(user, visit_ids, status)
      @user = user
      @visit_ids = visit_ids
      @status = status
      @errors = []
    end

    def call
      validate
      return false if errors.any?

      update_visits
    end

    private

    def validate
      if visit_ids.blank?
        errors << I18n.t('services.visits.bulk_update.none_selected')
        return
      end

      return if Visit.statuses.keys.include?(status)

      errors << I18n.t('services.visits.bulk_update.invalid_status')
    end

    def update_visits
      # scoped_visits so hidden rows (tombstones, declines, plan-archived)
      # can never be resurrected through a bulk status toggle.
      visits = user.scoped_visits.where(id: visit_ids)

      if visits.empty?
        errors << I18n.t('services.visits.bulk_update.none_found')
        return false
      end

      # Captured before update_all: declined visits drop out of scoped_visits.
      declined_place_ids = status == 'declined' ? visits.where.not(place_id: nil).distinct.pluck(:place_id) : []

      updated_count = visits.update_all(status: status)
      # rubocop:enable Rails/SkipsModelValidations

      # update_all skips AR callbacks, so declining here must enqueue the
      # orphan-place check the model runs on single-record declines.
      declined_place_ids.each { |place_id| Places::DeleteIfOrphanJob.perform_later(place_id) }

      { count: updated_count, visits: visits }
    end
  end
end
