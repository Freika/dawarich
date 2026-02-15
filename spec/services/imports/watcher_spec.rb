# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::Watcher do
  describe '#call' do
    subject(:service) { described_class.new.call }

    let(:watched_dir_path) { Rails.root.join('spec/fixtures/files/watched') }

    before do
      Sidekiq::Testing.inline!
      stub_const('Imports::Watcher::WATCHED_DIR_PATH', watched_dir_path)
    end

    after { Sidekiq::Testing.fake! }

    context 'when user exists' do
      let!(:user) { create(:user, email: 'user@domain.com') }

      it 'creates an import for the user' do
        expect { service }.to change(user.imports, :count).by(6)
      end

      it 'enqueues importing jobs for the user' do
        expect { service }.to have_enqueued_job(Import::ProcessJob).exactly(6).times
      end

      context 'when the import already exists' do
        it 'does not create a new import' do
          create(:import, user:, name: '2023_January.json')
          create(:import, user:, name: 'export_same_points.json')
          create(:import, user:, name: 'gpx_track_single_segment.gpx')
          create(:import, user:, name: 'location-history.json')
          create(:import, user:, name: 'owntracks.rec')
          create(:import, user:, name: 'Records.json')

          expect { service }.not_to change(Import, :count)
        end
      end
    end

    context 'when user does not exist' do
      it 'does not call Import::ProcessJob' do
        expect { service }.not_to have_enqueued_job(Import::ProcessJob)
      end

      it 'does not create an import' do
        expect { service }.not_to change(Import, :count)
      end
    end
  end
end
