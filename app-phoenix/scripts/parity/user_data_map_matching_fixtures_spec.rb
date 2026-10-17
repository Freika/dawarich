# frozen_string_literal: true

require 'rails_helper'
require_relative 'user_data_fixtures_support'

RSpec.describe 'Phoenix fixtures: user data map matching' do
  include ActiveSupport::Testing::TimeHelpers
  self.use_transactional_tests = false

  around { |example| Time.use_zone('UTC') { travel_to(Time.utc(2026, 10, 2, 12)) { example.run } } }

  it 'leaves archive corpus files untouched unless explicitly regenerating' do
    Dir.mktmpdir do |directory|
      stub_const('UserDataFixturesSupport::DIR', Pathname.new(directory))
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('WRITE_PHOENIX_FIXTURES').and_return(nil)
      UserDataFixturesSupport.save_entries('existing', 'tracks.jsonl' => "synthetic\n")
      expect(Dir.children(directory)).to be_empty
      allow(ENV).to receive(:[]).with('WRITE_PHOENIX_FIXTURES').and_return('1')
      UserDataFixturesSupport.save_entries('existing', 'tracks.jsonl' => "synthetic\n")
      expect(File.binread(File.join(directory, 'existing/entries/tracks.jsonl'))).to eq("synthetic\n")
    end
  end

  it 'captures current Track export bytes and old and new archive restore policy' do
    capture = { 'exports' => {}, 'matched' => {}, 'restores' => {} }
    %w[UTC Europe/Berlin America/New_York].each do |zone|
      Time.use_zone(zone) do
        UserDataFixturesSupport.with_users do
          UserDataFixturesSupport.with_crypto do
            user = UserDataFixturesSupport.dataset(zone)
            entries = UserDataFixturesSupport.extracted(Users::ExportData.new(user).export)
            capture['exports'][zone] = entries.select { |name, _| name.start_with?('tracks/') }
            capture['matched'][zone] = [nil, 0, 1, 2, 3].map do |status|
              track = user.tracks.first
              track.update_columns(
                map_matching_status: status, map_matched_at: Time.utc(2026, 2, 1, 0, 15, 30, 123_456),
                map_matching_input_digest: 'synthetic-input-digest',
                map_matching_data: { 'z' => [{ 'nullable' => nil, 'flag' => false, 'speed' => 1.25 }],
                                     'a' => 'café <road>&', 'empty' => {} },
                matched_path: 'MULTILINESTRING((12.4 51.3,12.5 51.4),(12.5 51.4,12.6 51.5))'
              )
              Dir.mktmpdir do |directory|
                paths = Users::ExportData::Tracks.new(user, Pathname.new(directory)).call
                { 'status' => status, 'seed' => track.reload.attributes.slice(
                  'map_matching_status', 'map_matching_data', 'map_matching_input_digest', 'map_matched_at'
                ).merge('matched_path' => track.matched_path.as_text,
                        'map_matched_at' => track.map_matched_at.utc.iso8601(6)),
                  'bytes' => File.binread(File.join(directory, paths.first.delete_prefix('tracks/'))) }
              end
            end
          end
        end
      end
    end
    recorded = JSON.parse(UserDataFixturesSupport::DIR.join('map_matching_columns.json').read)
    old = JSON.parse(recorded.dig('restores', 'old_v2', 'entries', 'tracks/2026/2026-01.jsonl'))
    current = JSON.parse(capture.fetch('matched').fetch('UTC').last.fetch('bytes'))
    columns = %w[map_matching_status map_matching_data map_matching_input_digest map_matched_at matched_path]
    expect(old.keys).not_to include(*columns)
    expect(current.keys).to include(*columns)
    { 'old' => old, 'new' => current }.each do |shape, track|
      %w[v2 v2_root].each do |version|
        entries = case version
                  when 'v2_root' then { 'manifest.json' => { 'format_version' => 2 }.to_json,
                                        'tracks.jsonl' => "#{track.to_json}\n" }
                  else { 'manifest.json' => { 'format_version' => 2,
                                             'files' => { 'tracks' => ['tracks/2026/2026-01.jsonl'] } }.to_json,
                         'tracks/2026/2026-01.jsonl' => "#{track.to_json}\n" }
                  end
        UserDataFixturesSupport.with_users do
          user = UserDataFixturesSupport.owner
          restored = UserDataFixturesSupport.archive(entries) { |path| Users::ImportData.new(user, path).import }
          row = user.tracks.first
          expect(restored).to include(tracks_created: 1)
          expect(row.attributes.slice('map_matching_status', 'map_matched_at', 'matched_path',
                                      'map_matching_input_digest', 'map_matching_data'))
            .to eq('map_matching_status' => nil, 'map_matched_at' => nil, 'matched_path' => nil,
                   'map_matching_input_digest' => nil, 'map_matching_data' => {})
          capture['restores']["#{shape}_#{version}"] = { 'entries' => entries, 'result' => restored,
                                                     'track' => row.as_json(except: %w[id user_id]) }
        end
      end
    end
    UserDataFixturesSupport.write('map_matching_columns.json', capture)
  end
end
