# frozen_string_literal: true

class Users::DigestsMailer < ApplicationMailer
  helper Users::DigestsHelper
  helper CountryFlagHelper
  helper Users::DigestsMailerHelper

  SIGNIFICANT_MINUTES = 60

  def year_end_digest
    @user = params[:user]
    @digest = params[:digest]
    @distance_unit = @user.safe_settings.distance_unit || 'km'

    @daily_values = yearly_daily_values
    @monthly_distances = converted_monthly_distances
    @top_countries = significant_locations(@digest.time_spent_by_location.to_h['countries'])

    mail(
      to: @user.email,
      subject: "Your #{@digest.year} Year in Review - Dawarich"
    )
  end

  def monthly_digest
    @user = params[:user]
    @digest = params[:digest]
    @distance_unit = @user.safe_settings.distance_unit || 'km'

    @daily_distances = converted_monthly_distances
    @weekday_totals = weekday_totals(@daily_distances, @digest.year, @digest.month)
    @active_days = @daily_distances.values.count { |d| d.to_f.positive? }
    @top_countries = significant_locations(@digest.time_spent_by_location.to_h['countries'])
    @top_cities = significant_locations(@digest.time_spent_by_location.to_h['cities'])
    @first_countries = @digest.first_time_visits.to_h['countries'].to_a
    @first_cities = @digest.first_time_visits.to_h['cities'].to_a

    mail(
      to: @user.email,
      subject: "Your #{Date::MONTHNAMES[@digest.month]} #{@digest.year} in review — Dawarich"
    )
  end

  private

  def converted_monthly_distances
    @digest.monthly_distances.to_h.transform_keys(&:to_s).transform_values do |v|
      Users::Digest.convert_distance(v, @distance_unit)
    end
  end

  def weekday_totals(daily_distances, year, month)
    totals = Array.new(7, 0.0)
    daily_distances.each do |day_str, distance|
      wday = Date.new(year, month, day_str.to_i).wday
      totals[wday] += distance.to_f
    rescue ArgumentError
      next
    end
    (totals[1..6] + [totals[0]]).map(&:round)
  end

  def yearly_daily_values
    values = {}
    @user.stats.where(year: @digest.year).find_each do |stat|
      (stat.daily_distance || {}).each do |day_str, distance|
        values[Date.new(stat.year, stat.month, day_str.to_i)] =
          Users::Digest.convert_distance(distance, @distance_unit)
      rescue ArgumentError
        next
      end
    end
    values
  end

  def significant_locations(entries)
    entries.to_a.select { |entry| entry['minutes'].to_i > SIGNIFICANT_MINUTES }
  end
end
