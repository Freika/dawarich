# frozen_string_literal: true

class PendingImport < ApplicationRecord
  has_one_attached :file

  validates :original_filename, presence: true
  validates :origin, presence: true
  validates :expires_at, presence: true

  scope :claimable, -> { where(claimed_at: nil).where('expires_at > ?', Time.current) }
  scope :expired,   -> { where('expires_at <= ?', Time.current) }
end
