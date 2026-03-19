# frozen_string_literal: true

module Points
  class RawDataArchive < ApplicationRecord
    self.table_name = 'points_raw_data_archives'

    belongs_to :user
    has_many :points, dependent: :restrict_with_exception

    has_one_attached :file

    after_commit :remove_attached_file, on: :destroy

    validates :year, :month, :chunk_number, :point_count, presence: true
    validates :year, numericality: { greater_than: 1970, less_than: 2100 }
    validates :month, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 12 }
    validates :chunk_number, numericality: { greater_than: 0 }
    validates :point_count, numericality: { greater_than: 0 }
    validates :point_ids_checksum, presence: true

    validate :metadata_contains_expected_and_actual_counts

    scope :for_month, lambda { |user_id, year, month|
      where(user_id: user_id, year: year, month: month)
        .order(:chunk_number)
    }

    scope :recent, -> { where('archived_at > ?', 30.days.ago) }
    scope :old, -> { where('archived_at < ?', 1.year.ago) }

    def month_display
      Date.new(year, month, 1).strftime('%B %Y')
    end

    def filename
      "raw_data_archives/#{user_id}/#{year}/#{format('%02d', month)}/#{format('%03d', chunk_number)}.jsonl.gz"
    end

    def size_mb
      return 0 unless file.attached?

      (file.blob.byte_size / 1024.0 / 1024.0).round(2)
    end

    def verified?
      verified_at.present?
    end

    def count_mismatch?
      return false if metadata.blank?

      expected = metadata['expected_count']
      actual = metadata['actual_count']

      return false if expected.nil? || actual.nil?

      expected != actual
    end

    private

    def metadata_contains_expected_and_actual_counts
      return if metadata.blank?

      # Count fields were introduced in format_version 2; don't enforce on older archives
      return if metadata['format_version'].blank? || metadata['format_version'].to_i < 2

      return unless metadata['expected_count'].blank? || metadata['actual_count'].blank?

      errors.add(:metadata, 'must contain expected_count and actual_count')
    end

    def remove_attached_file
      file.purge_later
    end
  end
end
