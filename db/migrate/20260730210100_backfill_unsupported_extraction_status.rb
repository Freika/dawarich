# frozen_string_literal: true

class BackfillUnsupportedExtractionStatus < ActiveRecord::Migration[8.0]
  ADAPTER_SUPPORTED_SOURCES = [
    0, # google_semantic_history
    3, # google_phone_takeout
    13 # polarsteps
  ].freeze

  NOT_ATTEMPTED_STATUS = 0
  UNSUPPORTED_STATUS = 5

  disable_ddl_transaction!

  # `source NOT IN (...)` drops NULLs, which would leave source-less imports
  # advertising an extraction no adapter can run.
  def up
    Import.where(additional_data_extraction_status: NOT_ATTEMPTED_STATUS)
          .where('source IS NULL OR source NOT IN (?)', ADAPTER_SUPPORTED_SOURCES)
          .in_batches(of: 5_000)
          .update_all(additional_data_extraction_status: UNSUPPORTED_STATUS)
  end

  def down
    Import.where(additional_data_extraction_status: UNSUPPORTED_STATUS)
          .in_batches(of: 5_000)
          .update_all(additional_data_extraction_status: NOT_ATTEMPTED_STATUS)
  end
end
