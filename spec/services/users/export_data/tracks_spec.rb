# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ExportData::Tracks, type: :service do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user) }

  subject { service.call }

  describe '#call' do
    context 'legacy mode (no output directory)' do
      context 'when user has no tracks' do
        it 'returns an empty array' do
          expect(subject).to eq([])
        end
      end

      context 'when user has tracks' do
        let!(:track1) do
          create(:track, user: user, start_at: Time.utc(2024, 1, 15), end_at: Time.utc(2024, 1, 15, 1))
        end
        let!(:segment1) { create(:track_segment, track: track1, transportation_mode: :driving) }

        it 'returns all user tracks' do
          expect(subject).to be_an(Array)
          expect(subject.size).to eq(1)
        end

        it 'excludes user_id and id fields' do
          subject.each do |track_data|
            expect(track_data).not_to have_key('user_id')
            expect(track_data).not_to have_key('id')
          end
        end

        it 'serializes original_path as WKT string' do
          track_data = subject.first
          expect(track_data['original_path']).to be_a(String)
          expect(track_data['original_path']).to match(/^LINESTRING/)
        end

        it 'serializes dominant_mode as integer' do
          track_data = subject.first
          expect(track_data['dominant_mode']).to be_an(Integer)
        end

        it 'embeds track segments' do
          track_data = subject.first
          expect(track_data['segments']).to be_an(Array)
          expect(track_data['segments'].size).to eq(1)

          segment_data = track_data['segments'].first
          expect(segment_data).not_to have_key('track_id')
          expect(segment_data).not_to have_key('id')
          expect(segment_data['transportation_mode']).to eq('driving')
        end
      end
    end

    context 'monthly file mode' do
      let(:output_directory) { Rails.root.join('tmp/test_tracks_export') }
      let(:monthly_service) { described_class.new(user, output_directory) }

      before do
        FileUtils.mkdir_p(output_directory)
      end

      after do
        FileUtils.rm_rf(output_directory)
      end

      context 'with tracks from different months' do
        let!(:track_jan_2022) do
          create(:track, user: user,
                         start_at: Time.utc(2022, 1, 15, 8),
                         end_at: Time.utc(2022, 1, 15, 9))
        end
        let!(:track_jun_2022) do
          create(:track, user: user,
                         start_at: Time.utc(2022, 6, 20, 8),
                         end_at: Time.utc(2022, 6, 20, 9))
        end
        let!(:track_jan_2023) do
          create(:track, user: user,
                         start_at: Time.utc(2023, 1, 5, 8),
                         end_at: Time.utc(2023, 1, 5, 9))
        end

        it 'returns array of relative file paths' do
          result = monthly_service.call

          expect(result).to be_an(Array)
          expect(result).to include('tracks/2022/2022-01.jsonl')
          expect(result).to include('tracks/2022/2022-06.jsonl')
          expect(result).to include('tracks/2023/2023-01.jsonl')
        end

        it 'creates year directories' do
          monthly_service.call

          expect(File.directory?(output_directory.join('2022'))).to be true
          expect(File.directory?(output_directory.join('2023'))).to be true
        end

        it 'creates JSONL files with one track per line' do
          monthly_service.call

          jan_2022_file = output_directory.join('2022', '2022-01.jsonl')
          expect(File.exist?(jan_2022_file)).to be true

          lines = File.readlines(jan_2022_file)
          expect(lines.size).to eq(1)

          track_data = JSON.parse(lines.first)
          expect(track_data).not_to have_key('user_id')
          expect(track_data).not_to have_key('id')
          expect(track_data['original_path']).to match(/^LINESTRING/)
        end

        it 'returns paths sorted alphabetically' do
          result = monthly_service.call

          expect(result).to eq(result.sort)
        end
      end

      context 'with no tracks' do
        it 'returns empty array' do
          result = monthly_service.call

          expect(result).to eq([])
        end
      end

      it 'logs export information' do
        create(:track, user: user,
                       start_at: Time.utc(2024, 1, 15, 8),
                       end_at: Time.utc(2024, 1, 15, 9))

        expect(Rails.logger).to receive(:info).with(/Exported \d+ tracks to \d+ monthly files/)

        monthly_service.call
      end
    end
  end
end
