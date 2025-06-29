# frozen_string_literal: true

class Users::ExportData::Stats
  def initialize(user)
    @user = user
  end

  def call
    user.stats.as_json(except: %w[user_id id])
  end

  private

  attr_reader :user
end
