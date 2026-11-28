# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::TimeChunkProcessorJob do
  it 'loads only segmentation columns for the buffer while preserving device tracks and elevation' do
    user = create(:user)
    source = PointSource.create!(digest: SecureRandom.hex(16), tracker_id: 'stamped')
    first = Time.utc(2020, 6, 15, 12).to_i
    %w[legacy stamped].each_with_index do |tracker, device|
      3.times do |index|
        create(:point, user: user, timestamp: first + index * 60,
                       lonlat: "POINT(#{13.0 + index * 0.001} #{52.0 + device * 0.001})",
                       tracker_id: tracker, source_id: (source.id if device == 1),
                       altitude: 10.5 + index, raw_data: { large: 'payload' }, geodata: { large: 'payload' })
      end
    end
    session = Tracks::SessionManager.new(user.id).create_session
    statements = []
    chunk = { buffer_start_timestamp: first, buffer_end_timestamp: first + 120,
              start_timestamp: first, end_timestamp: first + 120, chunk_id: 'test' }
    ActiveSupport::Notifications.subscribed(->(*args) { statements << args.last[:sql] }, 'sql.active_record') do
      described_class.perform_now(user.id, session.session_id, chunk)
    end
    buffer_reads = statements.grep(/SELECT.*FROM "points".*timestamp.*BETWEEN/)
                             .reject { |sql| sql.include?('SELECT 1 AS one') }
    expect(buffer_reads.size).to eq(1)
    expect(buffer_reads.first.split('FROM').first).not_to match(/raw_data|geodata|accuracy|\*/)
    locked_reads = statements.grep(/SELECT.*FROM "points".*FOR UPDATE/)
    expect(locked_reads).not_to be_empty
    expect(locked_reads.map { |sql| sql.split('FROM').first }.join).not_to match(/raw_data|geodata|accuracy|\*/)
    tracks = user.tracks.order(:tracker_id)
    expect(tracks.pluck(:tracker_id)).to eq(%w[legacy stamped])
    expect(tracks.map(&:elevation_gain)).to eq([2, 2])
    expect(tracks.map(&:duration)).to eq([120, 120])
    expect(tracks.map(&:distance)).to all(be_positive)
    expect(user.points.where(track_id: nil)).not_to exist
    expect(session.get_session_data['completed_chunks']).to eq(1)
  ensure
    session&.cleanup_session
  end
end
