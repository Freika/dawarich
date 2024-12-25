# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Imports::Create do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user, import) }

  describe '#call' do
    context 'when source is google_semantic_history' do
      let(:import) { create(:import, source: 'google_semantic_history') }

      it 'calls the GoogleMaps::SemanticHistoryParser' do
        expect(GoogleMaps::SemanticHistoryParser).to \
          receive(:new).with(import, user.id).and_return(double(call: true))
        service.call
      end
    end

    context 'when source is google_phone_takeout' do
      let(:import) { create(:import, source: 'google_phone_takeout') }

      it 'calls the GoogleMaps::PhoneTakeoutParser' do
        expect(GoogleMaps::PhoneTakeoutParser).to \
          receive(:new).with(import, user.id).and_return(double(call: true))
        service.call
      end
    end

    context 'when source is owntracks' do
      let(:import) { create(:import, source: 'owntracks') }

      it 'calls the OwnTracks::ExportParser' do
        expect(OwnTracks::ExportParser).to \
          receive(:new).with(import, user.id).and_return(double(call: true))
        service.call
      end

      context 'when import is successful' do
        it 'creates a finished notification' do
          service.call

          expect(user.notifications.last.kind).to eq('info')
        end

        it 'schedules stats creating' do
          Sidekiq::Testing.inline! do
            expect { service.call }.to \
              have_enqueued_job(Stats::CalculatingJob).with(user.id, 2024, 3)
          end
        end

        it 'schedules visit suggesting' do
          Sidekiq::Testing.inline! do
            expect { service.call }.to have_enqueued_job(VisitSuggestingJob)
          end
        end

        it 'schedules reverse geocoding' do
          expect { service.call }.to \
            have_enqueued_job(EnqueueBackgroundJob).with('continue_reverse_geocoding', user.id)
        end
      end

      context 'when import fails' do
        before do
          allow(OwnTracks::ExportParser).to receive(:new).with(import, user.id).and_return(double(call: false))
        end

        it 'creates a failed notification' do
          service.call

          expect(user.notifications.last.kind).to eq('error')
        end
      end
    end

    context 'when source is gpx' do
      let(:import) { create(:import, source: 'gpx') }

      it 'calls the Gpx::TrackParser' do
        expect(Gpx::TrackParser).to \
          receive(:new).with(import, user.id).and_return(double(call: true))
        service.call
      end
    end

    context 'when source is geojson' do
      let(:import) { create(:import, source: 'geojson') }

      it 'calls the Geojson::ImportParser' do
        expect(Geojson::ImportParser).to \
          receive(:new).with(import, user.id).and_return(double(call: true))
        service.call
      end
    end

    context 'when source is immich_api' do
      let(:import) { create(:import, source: 'immich_api') }

      it 'calls the Photos::ImportParser' do
        expect(Photos::ImportParser).to \
          receive(:new).with(import, user.id).and_return(double(call: true))
        service.call
      end
    end

    context 'when source is photoprism_api' do
      let(:import) { create(:import, source: 'photoprism_api') }

      it 'calls the Photos::ImportParser' do
        expect(Photos::ImportParser).to \
          receive(:new).with(import, user.id).and_return(double(call: true))
        service.call
      end
    end
  end
end
