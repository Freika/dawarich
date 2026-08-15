# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::FullHistoryRedetectJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers
  # Modeled as an upgraded account: the release migration clears the stamp,
  # while new accounts are born with it (and with no history to redo).
  let(:user) { create(:user).tap { |u| u.update_columns(visits_redetected_at: nil) } }
  let(:base_ts) { 1_700_000_000 }

  before do
    5.times do |i|
      create(:point, user: user,
                     latitude: 52.5, longitude: 13.4, lonlat: 'POINT(13.4 52.5)',
                     timestamp: base_ts + i * 60, accuracy: 10, visit_id: nil)
    end
  end

  describe 'visit deletion' do
    it 'deletes suggested visits and preserves confirmed and declined visits' do
      suggested = create(:visit, user: user, status: :suggested,
                                  started_at: Time.zone.at(base_ts),
                                  ended_at: Time.zone.at(base_ts + 600),
                                  duration: 600, name: 'old')
      confirmed = create(:visit, user: user, status: :confirmed,
                                  started_at: Time.zone.at(base_ts + 700),
                                  ended_at: Time.zone.at(base_ts + 1300),
                                  duration: 600, name: 'home')
      declined  = create(:visit, user: user, status: :declined,
                                  started_at: Time.zone.at(base_ts + 1400),
                                  ended_at: Time.zone.at(base_ts + 1700),
                                  duration: 300, name: 'gym')

      described_class.new.perform(user.id)

      expect(Visit.where(id: suggested.id)).to be_empty
      expect(Visit.where(id: confirmed.id)).to exist
      expect(Visit.where(id: declined.id)).to exist
    end

    it 'preserves imported visits' do
      import = create(:import, user: user)
      imported = create(:visit, user: user, status: :suggested,
                                started_at: Time.zone.at(base_ts),
                                ended_at: Time.zone.at(base_ts + 600),
                                duration: 600, name: 'from the source file')
      imported.update_columns(import_id: import.id)

      described_class.new.perform(user.id)

      expect(Visit.where(id: imported.id)).to exist
    end

    it 'clears suggested visits without enqueueing a place-cleanup job per row' do
      place = create(:place, user: user)
      2.times do |i|
        create(:visit, user: user, status: :suggested,
                       started_at: Time.zone.at(base_ts + (i * 100)),
                       ended_at: Time.zone.at(base_ts + (i * 100) + 600),
                       duration: 600, name: 'old').update_columns(place_id: place.id)
      end

      expect { described_class.new.perform(user.id) }
        .to have_enqueued_job(Places::DeleteIfOrphanJob).with(place.id).once
    end

    it 'preserves tombstoned suggested visits so user-deleted visits are never re-suggested' do
      tombstone = create(:visit, user: user, status: :suggested, deleted_at: 1.day.ago,
                                 started_at: Time.zone.at(base_ts),
                                 ended_at: Time.zone.at(base_ts + 600),
                                 duration: 600, name: 'deleted by user')

      described_class.new.perform(user.id)

      expect(Visit.where(id: tombstone.id)).to exist
    end
  end

  describe 'orphan place cleanup' do
    it 'deletes orphaned user-owned photon places, keeps manual and global places' do
      photon  = create(:place, user: user, source: :photon, name: 'cafe')
      manual  = create(:place, user: user, source: :manual, name: 'home')
      global  = create(:place, user: nil,  source: :photon, name: 'park')

      create(:visit, user: user, status: :suggested, place: photon,
                     started_at: Time.zone.at(base_ts),
                     ended_at: Time.zone.at(base_ts + 600),
                     duration: 600, name: 'cafe')
      create(:visit, user: user, status: :confirmed, place: manual,
                     started_at: Time.zone.at(base_ts + 700),
                     ended_at: Time.zone.at(base_ts + 1300),
                     duration: 600, name: 'home')
      create(:visit, user: user, status: :confirmed, place: global,
                     started_at: Time.zone.at(base_ts + 1400),
                     ended_at: Time.zone.at(base_ts + 1700),
                     duration: 300, name: 'park')

      perform_enqueued_jobs(only: Places::DeleteIfOrphanJob) do
        described_class.new.perform(user.id)
      end

      expect(Place.where(id: photon.id)).to be_empty
      expect(Place.where(id: manual.id)).to exist
      expect(Place.where(id: global.id)).to exist
    end
  end

  describe 'cooldown timestamp' do
    it 'does not stamp visits_redetected_at when months fail' do
      allow(Visits::SmartDetect).to receive(:new).and_raise(ActiveRecord::StatementInvalid, 'boom')

      described_class.new.perform(user.id)

      expect(user.reload.visits_redetected_at).to be_nil
    end

    it 'sets visits_redetected_at on success' do
      user.update_columns(visits_redetected_at: nil)
      travel_to(Time.current) do
        expect { described_class.new.perform(user.id) }
          .to change { user.reload.visits_redetected_at&.to_i }.from(nil).to(Time.current.to_i)
      end
    end
  end

  describe 'failure handling' do
    it 'reports each failing month, sends a warning notification, and does not re-raise when SmartDetect fails' do
      allow_any_instance_of(Visits::SmartDetect).to receive(:call).and_raise(StandardError, 'boom')
      expect(ExceptionReporter).to receive(:call).with(instance_of(StandardError)).at_least(:once)

      expect { described_class.new.perform(user.id) }.not_to raise_error

      expect(user.notifications.where(kind: :warning)).to exist
      expect(user.reload.visits_redetected_at).to be_nil
    end

    it 'continues across months, completing successful ones when one month fails' do
      jan_ts = Time.utc(2024, 1, 15, 12, 0).to_i
      feb_ts = Time.utc(2024, 2, 15, 12, 0).to_i
      [jan_ts, feb_ts].each do |ts|
        3.times do |i|
          create(:point, user: user,
                         latitude: 52.5, longitude: 13.4, lonlat: 'POINT(13.4 52.5)',
                         timestamp: ts + i * 60, accuracy: 10, visit_id: nil)
        end
      end

      call_count = 0
      allow_any_instance_of(Visits::SmartDetect).to receive(:call) do
        call_count += 1
        call_count == 1 ? raise(StandardError, 'transient') : []
      end

      expect { described_class.new.perform(user.id) }.not_to raise_error

      warning = user.notifications.where(kind: :warning).last
      expect(warning).to be_present
      expect(warning.content).to match(/1 month failed/)
    end

    it 'persists French copy with singular month grammar in the user saved locale' do
      user.update!(settings: { 'locale' => 'fr' })
      allow_any_instance_of(Visits::SmartDetect).to receive(:call).and_raise(StandardError, 'boom')

      I18n.with_locale(:en) { described_class.new.perform(user.id) }

      warning = user.notifications.where(kind: :warning).last
      expect(warning.title).to eq('Redétection des visites partiellement terminée')
      expect(warning.content).to include('1 mois a échoué')
      expect(warning.content).not_to include('mois(s)')
    end

    it 'wraps the rest of perform in the outer rescue so non-month errors still notify and re-raise' do
      allow(User).to receive(:find).and_call_original
      allow_any_instance_of(User).to receive(:points).and_raise(StandardError, 'db down')

      expect { described_class.new.perform(user.id) }.to raise_error(StandardError, /db down/)
      expect(user.notifications.where(kind: :error)).to exist
    end
  end

  describe 'no points' do
    it 'sends an info notification and does not raise' do
      empty_user = create(:user).tap { |u| u.update_columns(visits_redetected_at: nil) }
      expect { described_class.new.perform(empty_user.id) }.not_to raise_error
      expect(empty_user.notifications.where(kind: :info)).to exist
    end
  end
end
