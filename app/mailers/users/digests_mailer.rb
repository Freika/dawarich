# frozen_string_literal: true

class Users::DigestsMailer < ApplicationMailer
  helper Users::DigestsHelper
  helper CountryFlagHelper

  def year_end_digest
    @user = params[:user]
    @digest = params[:digest]
    @distance_unit = @user.safe_settings.distance_unit || 'km'

    mail(
      to: @user.email,
      subject: "Your #{@digest.year} Year in Review - Dawarich"
    )
  end
end
