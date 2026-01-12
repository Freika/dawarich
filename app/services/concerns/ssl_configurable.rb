# frozen_string_literal: true

module SslConfigurable
  extend ActiveSupport::Concern

  private

  def ssl_verification_enabled?(user, service_type)
    setting_key = "#{service_type}_skip_ssl_verification"
    # Return opposite of skip_ssl_verification (skip=true means verify=false)
    !user.settings[setting_key]
  end

  def http_options_with_ssl(user, service_type, base_options = {})
    base_options.merge(verify: ssl_verification_enabled?(user, service_type))
  end
end
