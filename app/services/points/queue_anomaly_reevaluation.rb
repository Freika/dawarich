# frozen_string_literal: true

module Points
  # Queues one re-evaluation of a user's past points against the GPS noise
  # filter at a time, shared by the points API and the Data processing page.
  class QueueAnomalyReevaluation
    PENDING_TTL = 30.minutes

    def initialize(user)
      @user = user
    end

    # Returns false while an earlier request for this user is still pending.
    def call
      return false unless Rails.cache.write("anomaly_backfill_pending:#{@user.id}", true,
                                            expires_in: PENDING_TTL, unless_exist: true)

      Points::AnomalyBackfillUserJob.perform_later(@user.id, reset: true)
      true
    end
  end
end
