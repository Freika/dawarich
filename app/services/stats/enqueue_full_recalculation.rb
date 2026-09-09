# frozen_string_literal: true

module Stats
  class EnqueueFullRecalculation
    def initialize(user)
      @user = user
    end

    def call
      user.years_tracked.each do |year|
        year[:months].each do |month|
          Stats::CalculatingJob.perform_later(user.id, year[:year], Date::ABBR_MONTHNAMES.index(month))
        end
      end
    end

    private

    attr_reader :user
  end
end
