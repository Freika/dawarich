# frozen_string_literal: true

class Users::ExportData::Trips
  def initialize(user)
    @user = user
  end

  def call
    user.trips.as_json(except: %w[user_id id])
  end

  private

  attr_reader :user
end
