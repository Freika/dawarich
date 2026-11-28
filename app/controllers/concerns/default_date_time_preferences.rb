# frozen_string_literal: true

module DefaultDateTimePreferences
  extend ActiveSupport::Concern

  private

  def apply_date_time_preferences(&)
    Users::DateTimePreferences.with(Users::DateTimePreferences::DEFAULT, &)
  end
end
