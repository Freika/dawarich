# frozen_string_literal: true

module Analytics
  # Records first_map_data_viewed once per account: the first time the map
  # loads a period that holds points from the user's own imports (not the
  # demo data, not tracker points). The browser sends the Rybbit event itself
  # on :recorded, so it joins the session that started the import.
  #
  # ponytail: "the loaded period holds imported points" stands in for "an
  # imported point was drawn in the viewport"; it does not check the viewport,
  # layer visibility or privacy zones. Flag the points in the vector tiles if
  # that difference ever matters.
  class FirstMapView
    def self.dedup_key(user)
      "first_map_data_viewed:#{user.id}"
    end

    def self.pending?(user)
      !DawarichSettings.self_hosted? &&
        user.imports.where(demo: false).exists? &&
        !AnalyticsEvent.exists?(dedup_key: dedup_key(user))
    end

    # period: a range of Unix timestamps.
    def initialize(user, period)
      @user = user
      @period = period
    end

    def call
      return :already_recorded if AnalyticsEvent.exists?(dedup_key: self.class.dedup_key(@user))
      return :no_imported_data unless imported_points_in_period?

      recorded = AnalyticsEvent.record(user: @user, event: :first_map_data_viewed,
                                       dedup_key: self.class.dedup_key(@user))
      recorded ? :recorded : :already_recorded
    end

    private

    def imported_points_in_period?
      @user.scoped_points
           .where(import_id: @user.imports.where(demo: false).select(:id))
           .where(timestamp: @period)
           .exists?
    end
  end
end
