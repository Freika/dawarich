# frozen_string_literal: true

module Users
  # Queues one rebuild of a user's tracks, stats and digests at a time. The
  # recalculations API and the Data processing settings page share the
  # pending key, so a click on each side still queues a single job.
  class QueueDataRecalculation
    PENDING_TTL = 30.minutes

    def initialize(user, year: nil)
      @user = user
      @year = year
    end

    # Returns false while an earlier request for this user is still pending.
    def call
      return false unless Rails.cache.write("recalculation_pending:#{@user.id}", true,
                                            expires_in: PENDING_TTL, unless_exist: true)

      Users::RecalculateDataJob.perform_later(@user.id, year: @year)
      true
    end
  end
end
