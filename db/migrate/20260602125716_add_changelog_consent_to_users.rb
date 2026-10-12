# frozen_string_literal: true

class AddChangelogConsentToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :changelog_consent, :integer, if_not_exists: true
  end
end
