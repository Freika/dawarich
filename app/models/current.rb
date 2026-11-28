# frozen_string_literal: true

class Current < ActiveSupport::CurrentAttributes
  attribute :date_time_preferences

  def date_time_preferences
    super || Users::DateTimePreferences::DEFAULT
  end
end
