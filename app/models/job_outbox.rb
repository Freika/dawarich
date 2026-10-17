# frozen_string_literal: true

class JobOutbox < ApplicationRecord
  self.table_name = 'job_outbox'
  self.primary_key = 'event_id'

  scope :pending, -> { where(state: 'pending') }
  scope :quarantined, -> { where(state: 'quarantined') }
end
