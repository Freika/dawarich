# frozen_string_literal: true

class AddDeletedAtToVisits < ActiveRecord::Migration[8.0]
  def change
    add_column :visits, :deleted_at, :datetime
  end
end
