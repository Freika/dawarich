# frozen_string_literal: true

module Tracks
  # Encapsulates filtering and pagination logic for API track listings
  class IndexQuery
    DEFAULT_PER_PAGE = 100

    def initialize(user:, params: {})
      @user = user
      @params = params.with_indifferent_access
    end

    def call
      scoped = user.tracks
      scoped = apply_date_range(scoped)

      scoped
        .order(start_at: :desc)
        .page(page_param)
        .per(per_page_param)
    end

    def pagination_headers(paginated_relation)
      {
        'X-Current-Page' => paginated_relation.current_page.to_s,
        'X-Total-Pages' => paginated_relation.total_pages.to_s,
        'X-Total-Count' => paginated_relation.total_count.to_s
      }
    end

    private

    attr_reader :user, :params

    def page_param
      candidate = params[:page].to_i
      candidate.positive? ? candidate : 1
    end

    def per_page_param
      candidate = params[:per_page].to_i
      candidate.positive? ? candidate : DEFAULT_PER_PAGE
    end

    def apply_date_range(scope)
      return scope unless params[:start_at].present? && params[:end_at].present?

      start_at = parse_timestamp(params[:start_at])
      end_at = parse_timestamp(params[:end_at])
      return scope if start_at.blank? || end_at.blank?

      scope.where('end_at >= ? AND start_at <= ?', start_at, end_at)
    end

    def parse_timestamp(value)
      Time.zone.parse(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
