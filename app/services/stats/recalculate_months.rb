# frozen_string_literal: true

class Stats::RecalculateMonths
  def initialize(user, months)
    @user = user
    @months = months
  end

  def call
    I18n.with_locale(user.locale) do
      months.each { |year, month| Stats::CalculateMonth.new(user.id, year, month, notify_on_failure: false).call }
      refresh_digests
    end
  end

  private

  attr_reader :user, :months

  def refresh_digests
    months.each do |year, month|
      next unless user.digests.monthly.exists?(year:, month:)

      Users::Digests::CalculateMonth.new(user.id, year, month).call
    end
    months.map(&:first).uniq.each do |year|
      Users::Digests::CalculateYear.new(user.id, year).call if user.digests.yearly.exists?(year:)
    end
  end
end
