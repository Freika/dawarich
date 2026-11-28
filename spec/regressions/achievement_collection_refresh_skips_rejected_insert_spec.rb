# frozen_string_literal: true

require 'rails_helper'

# Every rejected INSERT is an ERROR line in the PostgreSQL log, and the refresh
# cron reaches an existing row every five minutes for every user.
RSpec.describe 'Achievement collection refresh with an existing state' do
  let(:user) { create(:user) }

  def collection_state_inserts(&block)
    statements = []
    callback = lambda do |*, payload|
      sql = payload[:sql]
      statements << sql if sql.start_with?('INSERT INTO "achievement_collection_states"')
    end
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    statements
  end

  it 'reads the existing row instead of attempting an insert' do
    Achievements::CollectionState.create!(user_id: user.id)

    inserts = collection_state_inserts do
      Achievements::CollectionSchedule.call(user)
      Achievements::CollectionChecker.new(user, notify: false).call
    end

    expect(inserts).to be_empty
    expect(Achievements::CollectionState.where(user_id: user.id).count).to eq(1)
  end

  it 'still creates the state for a user who has none' do
    expect { Achievements::CollectionSchedule.call(user) }
      .to change { Achievements::CollectionState.where(user_id: user.id).count }.from(0).to(1)
  end
end
