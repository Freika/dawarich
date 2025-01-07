# frozen_string_literal: true

class Telemetry::Gather
  def initialize(measurement: 'dawarich_usage_metrics')
    @measurement = measurement
  end

  def call
    {
      measurement:,
      timestamp: Time.current.to_i,
      tags: { instance_id: },
      fields: { dau:, app_version: }
    }
  end

  private

  attr_reader :measurement

  def instance_id
    @instance_id ||= Digest::SHA2.hexdigest(User.first.api_key)
  end

  def app_version
    "\"#{APP_VERSION}\""
  end

  def dau
    User.where(last_sign_in_at: Time.zone.today.beginning_of_day..Time.zone.today.end_of_day).count
  end
end
