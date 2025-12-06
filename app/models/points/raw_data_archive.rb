# frozen_string_literal: true

module Points
  class RawDataArchive < ApplicationRecord
    self.table_name = 'points_raw_data_archives'

    belongs_to :user
    has_many :points, foreign_key: :raw_data_archive_id, dependent: :nullify

    has_one_attached :file

    validates :year, :month, :chunk_number, :point_count, presence: true
    validates :year, numericality: { greater_than: 1970, less_than: 2100 }
    validates :month, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 12 }
    validates :chunk_number, numericality: { greater_than: 0 }
    validates :point_ids_checksum, presence: true

    validate :file_must_be_attached, on: :update

    scope :for_month, ->(user_id, year, month) {
      where(user_id: user_id, year: year, month: month)
        .order(:chunk_number)
    }

    scope :recent, -> { where('archived_at > ?', 30.days.ago) }
    scope :old, -> { where('archived_at < ?', 1.year.ago) }

    def month_display
      Date.new(year, month, 1).strftime('%B %Y')
    end

    def filename
      "raw_data_#{user_id}_#{year}_#{format('%02d', month)}_chunk#{format('%03d', chunk_number)}.jsonl.gz"
    end

    def size_mb
      return 0 unless file.attached?

      (file.blob.byte_size / 1024.0 / 1024.0).round(2)
    end

    private

    def file_must_be_attached
      errors.add(:file, 'must be attached') unless file.attached?
    end
  end
end
