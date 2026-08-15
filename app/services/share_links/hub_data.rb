# frozen_string_literal: true

module ShareLinks
  class HubData
    def initialize(user, start_date: nil, end_date: nil)
      @user = user
      @start_date = start_date
      @end_date = end_date
    end

    def all_shares
      @all_shares ||= active.order(created_at: :desc).to_a
    end

    def live_share
      all_shares.find { |share| share.resource_type == 'live' }
    end

    def timeline_share
      all_shares.find { |share| share.resource_type == 'timeline' }
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
