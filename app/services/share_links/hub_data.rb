# frozen_string_literal: true

module ShareLinks
  class HubData
    def initialize(user, start_date: nil, end_date: nil, import_id: nil)
      @user = user
      @start_date = start_date
      @end_date = end_date
      @import_id = import_id.presence
    end

    def all_shares
      @all_shares ||= active.order(created_at: :desc).to_a
    end

    def live_share
      all_shares.find { |share| share.resource_type == 'live' }
    end

    def timeline_share
      all_shares.find do |share|
        share.timeline? && share.settings['import_id'].to_s == import_id.to_s
      end
    end

    attr_reader :import_id

    def timeline_settings
      dates = { 'start_date' => default_start_date.iso8601, 'end_date' => default_end_date.iso8601 }
      import_id ? dates.merge('import_id' => import_id.to_s) : dates
    end

    def any_shares?
      all_shares.any?
    end

    def default_start_date
      parse_date(@start_date) || 7.days.ago.to_date
    end

    def default_end_date
      parse_date(@end_date) || Date.current
    end

    private

    def active
      @user.shared_links.active
    end

    def parse_date(value)
      return nil if value.blank?

      Date.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
