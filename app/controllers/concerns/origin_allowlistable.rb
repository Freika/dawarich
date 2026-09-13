# frozen_string_literal: true

module OriginAllowlistable
  extend ActiveSupport::Concern

  ALLOWED_ORIGIN_PATTERNS = [
    %r{\Ahttps://dawarich\.app\z},
    %r{\Ahttps://[a-z0-9-]+\.dawarich\.pages\.dev\z}
  ].freeze

  DEV_ORIGIN_PATTERNS = [
    %r{\Ahttp://localhost(?::\d+)?\z}
  ].freeze

  def enforce_origin_allowlist!
    origin = request.origin.to_s
    return if patterns.any? { |re| re.match?(origin) }

    head :forbidden
  end

  private

  def patterns
    Rails.env.production? ? ALLOWED_ORIGIN_PATTERNS : ALLOWED_ORIGIN_PATTERNS + DEV_ORIGIN_PATTERNS
  end
end
