# frozen_string_literal: true

module Maps
  class HexagonContextResolver
    class SharedStatsNotFoundError < StandardError; end

    def self.call(params:, user: nil)
      new(params: params, user: user).call
    end

    def initialize(params:, user: nil)
      @params = params
      @user = user
    end

    def call
      return resolve_public_sharing_context if public_sharing_request?

      resolve_authenticated_context
    end

    private

    attr_reader :params, :user

    def public_sharing_request?
      params[:uuid].present?
    end

    def resolve_public_sharing_context
      stat = Stat.find_by(sharing_uuid: params[:uuid])

      raise SharedStatsNotFoundError, 'Shared stats not found or no longer available' unless stat&.public_accessible?

      target_user = stat.user
      start_date = Date.new(stat.year, stat.month, 1).beginning_of_day.iso8601
      end_date = Date.new(stat.year, stat.month, 1).end_of_month.end_of_day.iso8601

      {
        target_user: target_user,
        start_date: start_date,
        end_date: end_date,
        stat: stat
      }
    end

    def resolve_authenticated_context
      {
        user: user,
        start_date: params[:start_date],
        end_date: params[:end_date],
        stat: nil
      }
    end
  end
end
