# frozen_string_literal: true

class Families::UpdateLocationSharing
  Result = Struct.new(:success?, :payload, :status, keyword_init: true)

  def initialize(user:, enabled:, duration:)
    @user = user
    @enabled_param = enabled
    @duration_param = duration
    @boolean_caster = ActiveModel::Type::Boolean.new
  end

  def call
    if update_location_sharing
      success_result
    else
      failure_result('Failed to update location sharing setting', :unprocessable_content)
    end
  rescue => error
    Rails.logger.error("Failed to update family location sharing: #{error.message}") if defined?(Rails)
    failure_result('An error occurred while updating location sharing', :internal_server_error)
  end

  private

  attr_reader :user, :enabled_param, :duration_param, :boolean_caster

  def update_location_sharing
    user.update_family_location_sharing!(enabled?, duration: duration_param)
  end

  def enabled?
    @enabled ||= boolean_caster.cast(enabled_param)
  end

  def success_result
    payload = {
      success: true,
      enabled: enabled?,
      duration: user.family_sharing_duration,
      message: build_sharing_message
    }

    if enabled? && user.family_sharing_expires_at.present?
      payload[:expires_at] = user.family_sharing_expires_at.iso8601
      payload[:expires_at_formatted] = user.family_sharing_expires_at.strftime('%b %d at %I:%M %p')
    end

    Result.new(success?: true, payload: payload, status: :ok)
  end

  def failure_result(message, status)
    Result.new(success?: false, payload: { success: false, message: message }, status: status)
  end

  def build_sharing_message
    return 'Location sharing disabled' unless enabled?

    case duration_param
    when '1h' then 'Location sharing enabled for 1 hour'
    when '6h' then 'Location sharing enabled for 6 hours'
    when '12h' then 'Location sharing enabled for 12 hours'
    when '24h' then 'Location sharing enabled for 24 hours'
    when 'permanent', nil then 'Location sharing enabled'
    else
      duration_param.to_i.positive? ? "Location sharing enabled for #{duration_param.to_i} hours" : 'Location sharing enabled'
    end
  end
end
