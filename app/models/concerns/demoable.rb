# frozen_string_literal: true

module Demoable
  extend ActiveSupport::Concern

  included do
    scope :demo, -> { where(demo: true) }
  end

  def adopt!
    return unless demo?

    update_columns(demo: false, updated_at: Time.current)
  end
end
