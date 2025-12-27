# frozen_string_literal: true

class YearlyDigestsMailer < ApplicationMailer
  helper YearlyDigestsHelper

  def year_end_digest
    @user = params[:user]
    @digest = params[:digest]
    @distance_unit = @user.safe_settings.distance_unit || 'km'

    # Generate chart image
    @chart_image_name = generate_chart_attachment

    mail(
      to: @user.email,
      subject: "Your #{@digest.year} Year in Review - Dawarich"
    )
  end

  private

  def generate_chart_attachment
    image_data = YearlyDigests::ChartImageGenerator.new(@digest, distance_unit: @distance_unit).call
    filename = 'monthly_distance_chart.png'

    attachments.inline[filename] = {
      mime_type: 'image/png',
      content: image_data
    }

    filename
  rescue StandardError => e
    Rails.logger.error("Failed to generate chart image: #{e.message}")
    nil
  end
end
