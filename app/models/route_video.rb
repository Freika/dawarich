# frozen_string_literal: true

# A route replay video the browser rendered and handed back for safekeeping.
#
# The MP4 is rendered client-side (WebCodecs) and direct-uploaded, so the
# server never encodes anything. `settings` stores the full recipe the studio
# used, which makes a video reproducible: when retention purges the blob the
# row survives as `expired` and the studio can render it again from the same
# settings.
class RouteVideo < ApplicationRecord
  belongs_to :user

  enum :status, { stored: 0, expired: 1 }, prefix: :status

  validates :name, presence: true

  has_one_attached :file

  scope :newest_first, -> { order(created_at: :desc) }

  # The per-user cap is a rolling window rather than a wall: whoever is past it
  # loses their oldest files, not their newest save. Shared by the nightly
  # sweep and by the save that pushes a user over. Returns what it expired so
  # the caller can redraw those cards.
  def self.expire_over_cap(user_id, cap = DawarichSettings.video_max_per_user)
    return [] unless cap.positive?

    status_stored.with_attached_file
                 .where(user_id: user_id)
                 .newest_first
                 .offset(cap)
                 .each(&:expire!)
  end

  # Drops the blob but keeps the recipe. Idempotent: an already expired video
  # stays expired, and a row whose blob is already gone still flips status.
  def expire!
    file.purge_later if file.attached?
    update!(status: :expired, expired_at: Time.current)
  end

  def playable?
    status_stored? && file.attached?
  end
end
