# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Imports::DestroyCommands' do
  let(:commands) { Imports::DestroyCommands }
  let!(:user) { create(:user) }
  let!(:import) { create(:import, user:, status: :deleting, skip_background_processing: true) }
  let(:event) { SecureRandom.uuid }
  let(:payload) { { 'import_id' => import.id, 'user_id' => user.id, 'event_id' => event } }

  before { phoenix_tables! }

  def receipt(phase = 'requested')
    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      INSERT INTO phoenix.import_destroy_runs(import_id,user_id,event_id,phase,native_fallback)
      VALUES(#{import.id},#{user.id},'#{event}','#{phase}',#{phase == 'handback'})
    SQL
  end

  it 'queues an actor-scoped legacy request with its original event' do
    receipt
    expect { RailsCommands::Registry.handler('imports.destroy_requested').call(payload) }
      .to have_enqueued_job(Imports::DestroyJob)
      .with(import.id, expected_user_id: user.id, event_id: event)
  end

  it 'refuses a different actor or replaced request' do
    receipt
    expect { commands.requested(payload.merge('user_id' => create(:user).id)) }.not_to have_enqueued_job
    expect { commands.requested(payload.merge('event_id' => SecureRandom.uuid)) }.not_to have_enqueued_job
  end

  it 'debounces the actual achievement rebuild and retains the oldest deletion timestamp' do
    receipt
    clear_achievement_checks(user.id)
    args = payload.merge('oldest_timestamp' => 1_640_995_200)
    expect { 2.times { commands.achievements(args) } }.to have_enqueued_job(Achievements::CheckJob).once
    expect(Achievements::PendingChecks.read(user.id).first).to eq(1_640_995_200)
  end

  it 'routes adopted track reclassification through its actual native owner' do
    receipt
    track = create(:track, user:)
    job_owner!('command:transportation.reclassify_track', :oban)
    commands.callbacks(payload.merge('step' => 'reclassify_tracks', 'track_ids' => [track.id]))
    row = JobOutbox.pending.where(command_type: 'transportation.reclassify_track').sole
    expect(row.payload).to eq('track_id' => track.id, 'report_progress' => false, 'user_id' => nil)
  end

  it 'cannot reclassify a foreign track' do
    receipt
    track = create(:track)
    job_owner!('command:transportation.reclassify_track', :oban)
    commands.callbacks(payload.merge('step' => 'reclassify_tracks', 'track_ids' => [track.id]))
    expect(JobOutbox.where(command_type: 'transportation.reclassify_track')).to be_empty
  end

  it 'runs the real bulk stats sweep only with a terminal receipt and missing import' do
    receipt('removed')
    Import.where(id: import.id).delete_all
    commands.stats(payload)
    expect(user.reload.stats_swept_at).not_to be_nil
  end

  it 'refuses forged terminal receipts and a still-existing import' do
    receipt('removed')
    commands.stats(payload)
    expect(user.reload.stats_swept_at).to be_nil
    Import.where(id: import.id).delete_all
    commands.stats(payload.merge('event_id' => SecureRandom.uuid))
    expect(user.reload.stats_swept_at).to be_nil
  end

  it 'publishes removal only after the captured import is absent' do
    receipt('removed')
    Import.where(id: import.id).delete_all
    expect(ImportsChannel).to receive(:broadcast_to).with(user, action: 'delete', import: { id: import.id })
    commands.complete(payload)
  end
  it 'runs terminal handback orphan cleanup and stats with the retained actor receipt' do
    receipt('removed')
    track = create(:track, user:)
    segment = create(:track_segment, track:)
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL.squish)
      UPDATE phoenix.import_destroy_runs SET native_fallback=true,
        context=#{connection.quote({ track_ids: [track.id] }.to_json)}
      WHERE import_id=#{import.id}
    SQL
    Import.where(id: import.id).delete_all
    commands.terminal(payload)
    expect(Track.exists?(track.id)).to be false
    expect(TrackSegment.exists?(segment.id)).to be false
    expect(user.reload.stats_swept_at).not_to be_nil
    commands.terminal(payload)
    expect(Track.exists?(track.id)).to be false
  end

  it 'refuses terminal handback without its durable fallback bit' do
    receipt('removed')
    Import.where(id: import.id).delete_all
    commands.terminal(payload)
    expect(user.reload.stats_swept_at).to be_nil
  end
end
