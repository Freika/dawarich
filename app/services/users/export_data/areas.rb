# frozen_string_literal: true

class Users::ExportData::Areas
  def initialize(user)
    @user = user
  end

  def call
    user.areas.as_json(except: %w[user_id id])
  end

  private

  attr_reader :user
end
