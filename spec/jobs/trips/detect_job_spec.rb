# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trips::DetectJob do
  include ActiveSupport::Testing::TimeHelpers
  include Rails.application.routes.url_helpers

  let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin', 'locale' => 'en' }) }
  let(:place) { create(:place, user:, latitude: 52.52, longitude: 13.405) }

  def point_at(lon, lat, time)
    create(:point, user:, lonlat: "POINT(#{lon} #{lat})", timestamp: time.to_i)
  end

  def at_home(time) = point_at(13.405, 52.52, time)
  def in_lisbon(time) = point_at(-9.1393, 38.7223, time)
  def in_madrid(time) = point_at(-3.7038, 40.4168, time)

  before do
    create(:home, user:, place:)
    at_home(Time.utc(2026, 1, 1, 12))
    at_home(Time.utc(2026, 10, 10, 6))
    in_lisbon(Time.utc(2026, 10, 10, 14))
    in_lisbon(Time.utc(2026, 10, 14, 9))
    at_home(Time.utc(2026, 10, 14, 18))
  end

  it 'is queued on the trips queue' do
    expect(described_class.new.queue_name).to eq('trips')
  end

  it 'creates the trip and one notification that links to it' do
    expect { described_class.perform_now(user.id) }.to change(user.notifications, :count).by(1)
    trip = user.trips.origin_detected.last
    expect(user.notifications.last).to have_attributes(kind: 'info', content: include(trip_path(trip)))
    expect(user.notifications.last.title).to include(trip.name)
  end

  it 'sends one summary for several new trips' do
    in_madrid(Time.utc(2026, 10, 20, 14))
    in_madrid(Time.utc(2026, 10, 24, 9))
    at_home(Time.utc(2026, 10, 24, 18))

    expect { described_class.perform_now(user.id) }.to change(user.notifications, :count).by(1)
    expect(user.trips.origin_detected.count).to eq(2)
    expect(user.notifications.last).to have_attributes(
      kind: 'info',
      title: I18n.t('trip_detection.notifications.many.title', count: 2),
      content: include(trips_path(origin: 'detected'))
    )
  end

  it 'writes the notification in the language of the user' do
    user.update!(settings: user.settings.merge('locale' => 'de'))
    described_class.perform_now(user.id)
    expect(user.notifications.last.title).to eq(
      I18n.t('trip_detection.notifications.one.title', name: user.trips.sole.name, locale: :de)
    )
  end

  it 'sends nothing when the run creates nothing' do
    described_class.perform_now(user.id)
    expect { described_class.perform_now(user.id) }.not_to change(Notification, :count)
  end

  it 'does nothing when detection is switched off' do
    user.update!(settings: user.settings.merge('trip_detection_enabled' => 'false'))
    expect { described_class.perform_now(user.id) }.not_to change(Trip, :count)
    expect(user.notifications).to be_empty
  end

  context 'when another run holds the lock of the user' do
    def with_lock_held_elsewhere
      config = ActiveRecord::Base.connection_db_config.configuration_hash
      other = PG.connect(host: config[:host], port: config[:port], dbname: config[:database],
                         user: config[:username], password: config[:password])
      key = Trips::Detection::RunLock::NAMESPACE | user.id
      other.exec("SELECT pg_advisory_lock(#{key})")
      yield
    ensure
      other&.close
    end

    it 'creates nothing and runs again a minute later' do
      with_lock_held_elsewhere do
        freeze_time do
          expect { described_class.perform_now(user.id) }
            .to have_enqueued_job(described_class).with(user.id).at(1.minute.from_now)
          expect(user.trips).to be_empty
          expect(user.notifications).to be_empty
        end
      end
    end
  end

  it 'releases the lock of the user after a run' do
    described_class.perform_now(user.id)
    key = Trips::Detection::RunLock::NAMESPACE | user.id
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    other = PG.connect(host: config[:host], port: config[:port], dbname: config[:database],
                       user: config[:username], password: config[:password])
    expect(other.exec("SELECT pg_try_advisory_lock(#{key})").getvalue(0, 0)).to eq('t')
  ensure
    other&.close
  end

  it 'ignores a missing user' do
    expect { described_class.perform_now(0) }.not_to raise_error
  end
end
