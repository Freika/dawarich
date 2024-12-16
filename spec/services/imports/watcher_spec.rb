# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::Watcher do
  describe '#call' do
    subject(:service) { described_class.new.call }
    let(:watched_dir_path) { Rails.root.join('spec/fixtures/files/watched') }
    let(:user) { create(:user, email: 'user@domain.com') }

    before do
      FileUtils.mkdir_p(watched_dir_path.join(user.email))
      stub_const('Imports::Watcher::WATCHED_DIR_PATH', watched_dir_path)
    end

    after do
      FileUtils.rm_rf(watched_dir_path)
    end

    context 'when there are no files in the watched directory' do
      it 'does not call ImportJob' do
        expect(ImportJob).not_to receive(:perform_later)

        service
      end
    end

    context 'when there are files in the watched directory' do
      context 'when the file has a valid user email' do
        it 'creates an import for the user' do
          Sidekiq::Testing.inline!
          File.write(watched_dir_path.join(user.email, 'location-history.json'), '{"type": "FeatureCollection"}')
          File.write(watched_dir_path.join(user.email, 'Records.json'), '{"type": "FeatureCollection"}')
          File.write(watched_dir_path.join(user.email, '2023_January.json'), '{"type": "FeatureCollection"}')
          File.write(watched_dir_path.join(user.email, 'owntracks.rec'), '{"type": "FeatureCollection"}')
          File.write(watched_dir_path.join(user.email, 'gpx_track_single_segment.gpx'), '{"type": "FeatureCollection"}')
          
          expect { service }.to change(user.imports, :count).by(5)
        end
      end

      context 'when the file has an invalid user email' do
        it 'does not create an import' do
          FileUtils.mkdir_p(watched_dir_path.join('invalid@domain.com'))
          File.write(watched_dir_path.join('invalid@domain.com', 'location-history.json'), '{"type": "FeatureCollection"}')
          File.write(watched_dir_path.join('invalid@domain.com', 'Records.json'), '{"type": "FeatureCollection"}')
          File.write(watched_dir_path.join('invalid@domain.com', '2023_January.json'), '{"type": "FeatureCollection"}')
          File.write(watched_dir_path.join('invalid@domain.com', 'owntracks.rec'), '{"type": "FeatureCollection"}')
          File.write(watched_dir_path.join('invalid@domain.com', 'gpx_track_single_segment.gpx'), '{"type": "FeatureCollection"}')

         expect { service }.not_to change(Import, :count)
        end
      end

      context 'when the import already exists' do
        it 'does not create a new import' do
          create(:import, user:, name: 'export_same_points.json')
          create(:import, user:, name: 'gpx_track_single_segment.gpx')
          create(:import, user:, name: 'location-history.json')
          create(:import, user:, name: 'Records.json')
          create(:import, user:, name: '2023_January.json')
          create(:import, user:, name: 'data.geojson')
          
          expect { service }.not_to change(Import, :count)
        end
      end
    end
  end
end
