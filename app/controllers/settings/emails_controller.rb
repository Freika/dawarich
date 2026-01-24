# frozen_string_literal: true

class Settings::EmailsController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_active_user!, only: %i[update]

  def index; end

  def update
    current_user.settings['digest_emails_enabled'] = email_settings_params[:digest_emails_enabled]
    current_user.save!

    redirect_to settings_emails_path, notice: 'Email settings updated'
  end

  private

  def email_settings_params
    params.require(:emails).permit(:digest_emails_enabled)
  end
end
