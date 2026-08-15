# frozen_string_literal: true

class AddConfidenceToVisits < ActiveRecord::Migration[8.0]
  def change
    add_column :visits, :confidence, :smallint, if_not_exists: true
    add_column :visits, :confidence_breakdown, :jsonb, default: {}, null: false, if_not_exists: true
  end
end
