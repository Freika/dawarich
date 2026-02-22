# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ExportData::Visits, type: :service do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user) }

  subject { service.call }

  describe '#call' do
    context 'legacy mode (no output directory)' do
      context 'when user has no visits' do
        it 'returns an empty array' do
          expect(subject).to eq([])
        end
      end

      context 'when user has visits with places' do
        let(:place) { create(:place, name: 'Office Building', longitude: -73.9851, latitude: 40.7589, source: :manual) }
        let!(:visit_with_place) do
          create(:visit,
                 user: user,
                 place: place,
                 name: 'Work Visit',
                 started_at: Time.zone.parse('2024-01-01 08:00:00'),
                 ended_at: Time.zone.parse('2024-01-01 17:00:00'),
                 duration: 32_400,
                 status: :suggested)
        end

        it 'returns visits with place references' do
          expect(subject).to be_an(Array)
          expect(subject.size).to eq(1)
        end

        it 'excludes user_id, place_id, and id fields' do
          visit_data = subject.first

          expect(visit_data).not_to have_key('user_id')
          expect(visit_data).not_to have_key('place_id')
          expect(visit_data).not_to have_key('id')
        end

        it 'includes visit attributes and place reference' do
          visit_data = subject.first

          expect(visit_data).to include(
            'name' => 'Work Visit',
            'started_at' => visit_with_place.started_at,
            'ended_at' => visit_with_place.ended_at,
            'duration' => 32_400,
            'status' => 'suggested'
          )

          expect(visit_data['place_reference']).to eq({
                                                        'name' => 'Office Building',
            'latitude' => '40.7589',
            'longitude' => '-73.9851',
            'source' => 'manual'
                                                      })
        end

        it 'includes created_at and updated_at timestamps' do
          visit_data = subject.first

          expect(visit_data).to have_key('created_at')
          expect(visit_data).to have_key('updated_at')
        end
      end

      context 'when user has visits without places' do
        let!(:visit_without_place) do
          create(:visit,
                 user: user,
                 place: nil,
                 name: 'Unknown Location',
                 started_at: Time.zone.parse('2024-01-02 10:00:00'),
                 ended_at: Time.zone.parse('2024-01-02 12:00:00'),
                 duration: 7200,
                 status: :confirmed)
        end

        it 'returns visits with null place references' do
          visit_data = subject.first

          expect(visit_data).to include(
            'name' => 'Unknown Location',
            'duration' => 7200,
            'status' => 'confirmed'
          )
          expect(visit_data['place_reference']).to be_nil
        end
      end

      context 'with mixed visits (with and without places)' do
        let(:place) { create(:place, name: 'Gym', longitude: -74.006, latitude: 40.7128) }
        let!(:visit_with_place) { create(:visit, user: user, place: place, name: 'Workout') }
        let!(:visit_without_place) { create(:visit, user: user, place: nil, name: 'Random Stop') }

        it 'returns all visits with appropriate place references' do
          expect(subject.size).to eq(2)

          visit_with_place_data = subject.find { |v| v['name'] == 'Workout' }
          visit_without_place_data = subject.find { |v| v['name'] == 'Random Stop' }

          expect(visit_with_place_data['place_reference']).to be_present
          expect(visit_without_place_data['place_reference']).to be_nil
        end
      end

      context 'with multiple users' do
        let(:other_user) { create(:user) }
        let!(:user_visit) { create(:visit, user: user, name: 'User Visit') }
        let!(:other_user_visit) { create(:visit, user: other_user, name: 'Other User Visit') }

        it 'only returns visits for the specified user' do
          expect(subject.size).to eq(1)
          expect(subject.first['name']).to eq('User Visit')
        end
      end
    end

    context 'monthly file mode' do
      let(:output_directory) { Rails.root.join('tmp/test_visits_export') }
      let(:monthly_service) { described_class.new(user, output_directory) }

      before do
        FileUtils.mkdir_p(output_directory)
      end

      after do
        FileUtils.rm_rf(output_directory)
      end

      context 'with visits from different months' do
        let(:place) { create(:place, name: 'Office') }
        let!(:visit_jan_2022) do
          create(:visit,
                 user: user,
                 place: place,
                 name: 'Jan 2022 Visit',
                 started_at: Time.zone.parse('2022-01-15 08:00:00'),
                 ended_at: Time.zone.parse('2022-01-15 17:00:00'))
        end
        let!(:visit_jun_2022) do
          create(:visit,
                 user: user,
                 place: place,
                 name: 'Jun 2022 Visit',
                 started_at: Time.zone.parse('2022-06-20 08:00:00'),
                 ended_at: Time.zone.parse('2022-06-20 17:00:00'))
        end
        let!(:visit_jan_2023) do
          create(:visit,
                 user: user,
                 place: nil,
                 name: 'Jan 2023 Visit',
                 started_at: Time.zone.parse('2023-01-05 08:00:00'),
                 ended_at: Time.zone.parse('2023-01-05 17:00:00'))
        end

        it 'returns array of relative file paths' do
          result = monthly_service.call

          expect(result).to be_an(Array)
          expect(result).to include('visits/2022/2022-01.jsonl')
          expect(result).to include('visits/2022/2022-06.jsonl')
          expect(result).to include('visits/2023/2023-01.jsonl')
        end

        it 'creates year directories' do
          monthly_service.call

          expect(File.directory?(output_directory.join('2022'))).to be true
          expect(File.directory?(output_directory.join('2023'))).to be true
        end

        it 'creates JSONL files with one visit per line' do
          monthly_service.call

          jan_2022_file = output_directory.join('2022', '2022-01.jsonl')
          expect(File.exist?(jan_2022_file)).to be true

          lines = File.readlines(jan_2022_file)
          expect(lines.size).to eq(1)

          visit_data = JSON.parse(lines.first)
          expect(visit_data['name']).to eq('Jan 2022 Visit')
          expect(visit_data['place_reference']).to be_present
        end

        it 'groups visits by started_at month' do
          monthly_service.call

          # Check each file has exactly 1 visit
          expect(File.readlines(output_directory.join('2022', '2022-01.jsonl')).size).to eq(1)
          expect(File.readlines(output_directory.join('2022', '2022-06.jsonl')).size).to eq(1)
          expect(File.readlines(output_directory.join('2023', '2023-01.jsonl')).size).to eq(1)
        end

        it 'returns paths sorted alphabetically' do
          result = monthly_service.call

          expect(result).to eq(result.sort)
        end

        it 'preserves place references in JSONL output' do
          monthly_service.call

          jan_2023_file = output_directory.join('2023', '2023-01.jsonl')
          visit_data = JSON.parse(File.readlines(jan_2023_file).first)

          expect(visit_data['name']).to eq('Jan 2023 Visit')
          expect(visit_data['place_reference']).to be_nil
        end
      end

      context 'with no visits' do
        it 'returns empty array' do
          result = monthly_service.call

          expect(result).to eq([])
        end
      end

      context 'with no visits' do
        it 'does not create any files' do
          result = monthly_service.call

          expect(result).to eq([])
          expect(Dir.glob(output_directory.join('**', '*.jsonl')).size).to eq(0)
        end
      end

      it 'logs export information' do
        place = create(:place)
        create_list(:visit, 3, user: user, place: place)

        expect(Rails.logger).to receive(:info).with(/Exported \d+ visits to \d+ monthly files/)

        monthly_service.call
      end
    end
  end
end
