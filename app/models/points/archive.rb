# frozen_string_literal: true

module Points
  class Archive < ApplicationRecord
    self.table_name = 'points_archives'

    belongs_to :user

    has_one_attached :file

    after_commit :remove_attached_file, on: :destroy

    validates :year, :month, :chunk_number, :point_count, :point_ids_checksum, presence: true
    validates :year, numericality: { greater_than: 1970, less_than: 2100 }
    validates :month, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 12 }
    validates :chunk_number, numericality: { greater_than: 0 }
    validates :point_count, numericality: { greater_than: 0 }

    scope :for_month, ->(user_id, year, month) { where(user_id:, year:, month:).order(:chunk_number) }
    scope :verified, -> { where.not(verified_at: nil) }
    scope :deletable, ->(before) { verified.where(deleted_at: nil).where('verified_at < ?', before) }

    def storage_key
      "points_archives/#{user_id}/#{year}/#{format('%02d', month)}/#{format('%03d', chunk_number)}.jsonl.gz.enc"
    end

    def verified?
      verified_at.present?
    end

    private

    def remove_attached_file
      file.purge_later
    end
  end
end
