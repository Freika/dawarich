# frozen_string_literal: true

class DataMigrations::RecalculateUserFlightMonthsJob < ApplicationJob
  queue_as :stats

  def perform(user_id)
    user = find_user_or_skip(user_id) || return
    months = user.flights.stat_months(user.timezone_iana)

    I18n.with_locale(user.locale) do
      months.each { |year, month| Stats::CalculateMonth.new(user.id, year, month, notify_on_failure: false).call }
      refresh_digests(user, months)
    end
  end

  private

  def refresh_digests(user, months)
    months.each do |year, month|
      next unless user.digests.monthly.exists?(year:, month:)

      Users::Digests::CalculateMonth.new(user.id, year, month).call
    end
    months.map(&:first).uniq.each do |year|
      Users::Digests::CalculateYear.new(user.id, year).call if user.digests.yearly.exists?(year:)
    end
  end
end
