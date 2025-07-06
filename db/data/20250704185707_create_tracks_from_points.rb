# frozen_string_literal: true

class CreateTracksFromPoints < ActiveRecord::Migration[8.0]
  def up
    User.find_each do |user|
      Tracks::CreateJob.perform_later(user.id)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
