# frozen_string_literal: true

class AddSourceDigestToNotes < ActiveRecord::Migration[8.0]
  def change
    add_column :notes, :source_digest, :string
  end
end
