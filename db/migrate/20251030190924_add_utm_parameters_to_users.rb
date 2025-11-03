# frozen_string_literal: true

class AddUtmParametersToUsers < ActiveRecord::Migration[8.0]
  def change
    safety_assured do
      add_column :users, :utm_source, :string
      add_column :users, :utm_medium, :string
      add_column :users, :utm_campaign, :string
      add_column :users, :utm_term, :string
      add_column :users, :utm_content, :string
    end
  end
end
