# frozen_string_literal: true

class Users::ExportData::Places
  def initialize(user)
    @user = user
  end

  def call
    user.places.as_json(except: %w[user_id id])
  end

  private

  attr_reader :user
end
