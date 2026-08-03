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
      visits = user.visits.where(id: visit_ids)

      if visits.empty?
        errors << I18n.t('services.visits.bulk_update.none_found')
        return false
      end

      updated_count = visits.update_all(status: status)
      # rubocop:enable Rails/SkipsModelValidations

      { count: updated_count, visits: visits }
    end
  end
end
