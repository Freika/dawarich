# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::Watcher do
  describe '#call' do
    subject(:service) { described_class.new.call }

    let(:watched_dir_path) { Rails.root.join('spec/fixtures/files/watched') }
    let(:user) { create(:user, email: 'user@domain.com') }

    before do
      stub_const('Imports::Watcher::WATCHED_DIR_PATH', watched_dir_path)
    end

    context 'when there are no files in the watched directory' do
      it 'does not call ImportJob' do
        expect(ImportJob).not_to receive(:perform_later)

        service
      end
    end

    context 'when there are files in the watched directory' do
      Sidekiq::Testing.inline! do
        context 'when the file has a valid user email' do
          it 'creates an import for the user' do
            expect { service }.to change(user.imports, :count).by(2)
          end
        end

        context 'when the file has an invalid user email' do
          it 'does not create an import' do
            expect { service }.not_to change(Import, :count)
          end
        end

        context 'when the import already exists' do
          it 'does not create a new import' do
            create(:import, user:, name: 'export_same_points.json')
            create(:import, user:, name: 'gpx_track_single_segment.gpx')

            expect { service }.not_to change(Import, :count)
          end
        end
      end
    end
  end
end
