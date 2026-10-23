# frozen_string_literal: true

module Tracks
  class Revision < ApplicationRecord
    extend MonthlyRevisions

    self.table_name = 'track_revisions'
  end
end
