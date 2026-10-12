# frozen_string_literal: true

module DayBoundable
  extend ActiveSupport::Concern

  DATE_ONLY = /\A\d{4}-\d{1,2}-\d{1,2}\z/

  private

  # A search bound written as a bare date names a whole day, so an end bound in
  # that form has to be expanded to the day's last instant. A bound that already
  # carries a time means exactly what it says and is left alone.
  def date_only?(value)
    value.to_s.strip.match?(DATE_ONLY)
  end
end
