# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ExportData::Digests, type: :service do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user) }

  subject { service.call }

  describe '#call' do
    context 'legacy mode (no output directory)' do
      context 'when user has no digests' do
        it 'returns an empty array' do
          expect(subject).to eq([])
        end
      end

      context 'when user has digests' do
        let!(:digest1) { create(:users_digest, :monthly, user: user, year: 2024, month: 1) }
        let!(:digest2) { create(:users_digest, user: user, year: 2024) }

        it 'returns all user digests' do
          expect(subject).to be_an(Array)
          expect(subject.size).to eq(2)
        end

        it 'excludes user_id and id fields' do
          subject.each do |digest_data|
            expect(digest_data).not_to have_key('user_id')
            expect(digest_data).not_to have_key('id')
          end
        end

        it 'preserves JSONB columns' do
          digest_data = subject.find { |d| d['month'] == 1 }

          expect(digest_data['toponyms']).to be_present
          expect(digest_data['monthly_distances']).to be_present
          expect(digest_data['sharing_uuid']).to be_present
        end
      end
    end

    context 'monthly file mode' do
      let(:output_directory) { Rails.root.join('tmp/test_digests_export') }
      let(:monthly_service) { described_class.new(user, output_directory) }

      before do
        FileUtils.mkdir_p(output_directory)
      end

      after do
        FileUtils.rm_rf(output_directory)
      end

      context 'with digests from different months' do
        let!(:digest_jan_2022) { create(:users_digest, :monthly, user: user, year: 2022, month: 1) }
        let!(:digest_jun_2022) { create(:users_digest, :monthly, user: user, year: 2022, month: 6) }
        let!(:digest_yearly_2023) { create(:users_digest, user: user, year: 2023) }

        it 'returns array of relative file paths' do
          result = monthly_service.call

          expect(result).to be_an(Array)
          expect(result).to include('digests/2022/2022-01.jsonl')
          expect(result).to include('digests/2022/2022-06.jsonl')
          expect(result).to include('digests/2023/2023.jsonl')
        end

        it 'creates year directories' do
          monthly_service.call

          expect(File.directory?(output_directory.join('2022'))).to be true
          expect(File.directory?(output_directory.join('2023'))).to be true
        end

        it 'creates JSONL files with one digest per line' do
          monthly_service.call

          jan_2022_file = output_directory.join('2022', '2022-01.jsonl')
          expect(File.exist?(jan_2022_file)).to be true

          lines = File.readlines(jan_2022_file)
          expect(lines.size).to eq(1)

          digest_data = JSON.parse(lines.first)
          expect(digest_data['year']).to eq(2022)
          expect(digest_data['month']).to eq(1)
        end

        it 'returns paths sorted alphabetically' do
          result = monthly_service.call

          expect(result).to eq(result.sort)
        end

        it 'excludes user_id and id in JSONL output' do
          monthly_service.call

          jan_2022_file = output_directory.join('2022', '2022-01.jsonl')
          digest_data = JSON.parse(File.readlines(jan_2022_file).first)

          expect(digest_data).not_to have_key('user_id')
          expect(digest_data).not_to have_key('id')
        end
      end

      context 'with no digests' do
        it 'returns empty array' do
          result = monthly_service.call

          expect(result).to eq([])
        end
      end

      it 'logs export information' do
        create(:users_digest, :monthly, user: user, year: 2024, month: 1)

        expect(Rails.logger).to receive(:info).with(/Exported \d+ digests to \d+ monthly files/)

        monthly_service.call
      end
    end
  end
end
