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

  after_commit -> { file.purge_later if file.attached? }, on: :destroy

  scope :newest_first, -> { order(created_at: :desc) }

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
