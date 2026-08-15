# frozen_string_literal: true

class SettingsController < ApplicationController
  before_action :authenticate_user!

  CHANGELOG_DECISIONS = %w[granted declined].freeze

  def theme
    current_user.update(theme: params[:theme])

    redirect_back(fallback_location: root_path)
  end

  def changelog_consent
    decision = params[:decision].to_s
    return head :unprocessable_entity unless CHANGELOG_DECISIONS.include?(decision)

    current_user.update!(changelog_consent: decision)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back(fallback_location: root_path) }
    end
  end

  def generate_api_key
    current_user.update(api_key: SecureRandom.hex(32))

    redirect_back(fallback_location: root_path)
  end
end
