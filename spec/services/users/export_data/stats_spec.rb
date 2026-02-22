# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ExportData::Stats, type: :service do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user) }

  subject { service.call }

  describe '#call' do
    context 'legacy mode (no output directory)' do
      context 'when user has no stats' do
        it 'returns an empty array' do
          expect(subject).to eq([])
        end
      end

      context 'when user has stats' do
        let!(:stat1) { create(:stat, user: user, year: 2024, month: 1, distance: 100) }
        let!(:stat2) { create(:stat, user: user, year: 2024, month: 2, distance: 150) }

        it 'returns all user stats' do
          expect(subject).to be_an(Array)
          expect(subject.size).to eq(2)
        end

        it 'excludes user_id and id fields' do
          subject.each do |stat_data|
            expect(stat_data).not_to have_key('user_id')
            expect(stat_data).not_to have_key('id')
          end
        end

        it 'includes expected stat attributes' do
          stat_data = subject.find { |s| s['month'] == 1 }

          expect(stat_data).to include(
            'year' => 2024,
            'month' => 1,
            'distance' => 100
          )
          expect(stat_data).to have_key('created_at')
          expect(stat_data).to have_key('updated_at')
        end
      end

      context 'with multiple users' do
        let(:other_user) { create(:user) }
        let!(:user_stat) { create(:stat, user: user, year: 2024, month: 1) }
        let!(:other_user_stat) { create(:stat, user: other_user, year: 2024, month: 1) }

        it 'only returns stats for the specified user' do
          expect(subject.size).to eq(1)
        end
      end
    end

    context 'monthly file mode' do
      let(:output_directory) { Rails.root.join('tmp/test_stats_export') }
      let(:monthly_service) { described_class.new(user, output_directory) }

      before do
        FileUtils.mkdir_p(output_directory)
      end

      after do
        FileUtils.rm_rf(output_directory)
      end

      context 'with stats from different months' do
        let!(:stat_jan_2022) { create(:stat, user: user, year: 2022, month: 1, distance: 100) }
        let!(:stat_jun_2022) { create(:stat, user: user, year: 2022, month: 6, distance: 200) }
        let!(:stat_jan_2023) { create(:stat, user: user, year: 2023, month: 1, distance: 150) }

        it 'returns array of relative file paths' do
          result = monthly_service.call

          expect(result).to be_an(Array)
          expect(result).to include('stats/2022/2022-01.jsonl')
          expect(result).to include('stats/2022/2022-06.jsonl')
          expect(result).to include('stats/2023/2023-01.jsonl')
        end

        it 'creates year directories' do
          monthly_service.call

          expect(File.directory?(output_directory.join('2022'))).to be true
          expect(File.directory?(output_directory.join('2023'))).to be true
        end

        it 'creates JSONL files with one stat per line' do
          monthly_service.call

          jan_2022_file = output_directory.join('2022', '2022-01.jsonl')
          expect(File.exist?(jan_2022_file)).to be true

          lines = File.readlines(jan_2022_file)
          expect(lines.size).to eq(1)

          stat_data = JSON.parse(lines.first)
          expect(stat_data['year']).to eq(2022)
          expect(stat_data['month']).to eq(1)
          expect(stat_data['distance']).to eq(100)
        end

        it 'groups stats by their year/month fields' do
          monthly_service.call

          # Each file should have exactly 1 stat
          expect(File.readlines(output_directory.join('2022', '2022-01.jsonl')).size).to eq(1)
          expect(File.readlines(output_directory.join('2022', '2022-06.jsonl')).size).to eq(1)
          expect(File.readlines(output_directory.join('2023', '2023-01.jsonl')).size).to eq(1)
        end

        it 'returns paths sorted alphabetically' do
          result = monthly_service.call

          expect(result).to eq(result.sort)
        end

        it 'excludes user_id and id in JSONL output' do
          monthly_service.call

          jan_2022_file = output_directory.join('2022', '2022-01.jsonl')
          stat_data = JSON.parse(File.readlines(jan_2022_file).first)

          expect(stat_data).not_to have_key('user_id')
          expect(stat_data).not_to have_key('id')
        end
      end

      context 'with no stats' do
        it 'returns empty array' do
          result = monthly_service.call

          expect(result).to eq([])
        end
      end

      context 'with multiple stats in same month' do
        # Stats have unique constraint on (user_id, year, month) so we can't have duplicates
        # Instead, test that one stat per month works correctly
        let!(:stat1) { create(:stat, user: user, year: 2022, month: 1, distance: 100) }
        let!(:stat2) { create(:stat, user: user, year: 2022, month: 2, distance: 200) }

        it 'creates separate files for each month' do
          result = monthly_service.call

          expect(result.size).to eq(2)
          expect(result).to include('stats/2022/2022-01.jsonl')
          expect(result).to include('stats/2022/2022-02.jsonl')
        end
      end

      it 'logs export information' do
        # Create stats with different months to avoid unique constraint violation
        create(:stat, user: user, year: 2024, month: 1)
        create(:stat, user: user, year: 2024, month: 2)
        create(:stat, user: user, year: 2024, month: 3)

        expect(Rails.logger).to receive(:info).with(/Exported \d+ stats to \d+ monthly files/)

        monthly_service.call
      end
    end
  end
end
