# frozen_string_literal: true

module Points
  class ReadSummary
    def initialize(scope, user_id:)
      @scope = scope.except(:select, :order, :includes, :preload, :eager_load)
      @user_id = user_id
    end

    def call
      version = Revision.for_user(@user_id)
      key = ['points/read_summary/v1', @user_id, version, Digest::SHA256.hexdigest(@scope.to_sql)]
      Rails.cache.fetch(key, expires_in: 1.hour) do
        @scope.pick(Arel.sql('COUNT(*)'), Arel.sql('MAX(timestamp)'), Arel.sql('MAX(updated_at)')) || [0, nil, nil]
      end
    end

    def self.end_timestamp(user_id, requested_end)
      Point.where(user_id: user_id).where('timestamp <= ?', requested_end)
           .order(timestamp: :desc).pick(:timestamp)
    end

    def self.plan_scope(scope, user)
      return scope unless user.plan_restricted?

      first = user.points.where('timestamp >= ?', user.data_window_start.to_i).order(:timestamp).pick(:timestamp)
      first ? scope.where('timestamp >= ?', first) : scope.none
    end

    module Pagination
      attr_writer :cached_total_count

      def total_count(*)
        @cached_total_count || super
      end
    end
  end
end
