# frozen_string_literal: true

module Points
  class Revision < ApplicationRecord
    extend MonthlyRevisions

    self.table_name = 'point_revisions'
  end
end
