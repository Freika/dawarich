# frozen_string_literal: true

module Maps
  class HexagonContextResolver
    class SharedStatsNotFoundError < StandardError; end

    def self.call(params:, current_api_user: nil)
      new(params: params, current_api_user: current_api_user).call
    end

    def initialize(params:, current_api_user: nil)
      @params = params
      @current_api_user = current_api_user
    end

    def call
      return resolve_public_sharing_context if public_sharing_request?

      resolve_authenticated_context
    end

    private

    attr_reader :params, :current_api_user

    def public_sharing_request?
      params[:uuid].present?
    end

    def resolve_public_sharing_context
      stat = Stat.find_by(sharing_uuid: params[:uuid])

      unless stat&.public_accessible?
        raise SharedStatsNotFoundError, 'Shared stats not found or no longer available'
      end

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
        target_user: current_api_user,
        start_date: params[:start_date],
        end_date: params[:end_date],
        stat: nil
      }
    end
  end
end