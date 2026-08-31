# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Create do
  let(:user) { create(:user) }
  let(:valid_params) do
    {
      name: 'Test Visit',
      latitude: 52.52,
      longitude: 13.405,
      started_at: '2023-12-01T10:00:00Z',
      ended_at: '2023-12-01T12:00:00Z'
    }
  end

  describe '#call' do
    context 'when all parameters are valid' do
      subject(:service) { described_class.new(user, valid_params) }

      it 'creates a visit successfully' do
        expect { service.call }.to change { user.visits.count }.by(1)
        expect(service.visit).to be_persisted
      end

      it 'returns the existing visit instead of duplicating it on a repeated call' do
        first = described_class.new(user, valid_params)
        first.call

        expect { service.call }.not_to(change { user.visits.count })
        expect(service.call).to be_truthy
        expect(service.visit).to eq(first.visit)
      end

      it 'resurrects a tombstoned visit when the user re-creates it at the same place and time' do
        first = described_class.new(user, valid_params)
        first.call
        first.visit.soft_delete!

        expect(service.call).to be_truthy
        expect(service.visit.id).to eq(first.visit.id)
        expect(service.visit.reload.deleted_at).to be_nil
        expect(service.visit.status).to eq('confirmed')
      end

      it 'resurrects a declined (hidden but not tombstoned) visit on re-creation' do
        first = described_class.new(user, valid_params)
        first.call
        first.visit.update!(status: :declined)

        expect(service.call).to be_truthy
        expect(service.visit.id).to eq(first.visit.id)
        expect(service.visit.reload.status).to eq('confirmed')
      end

      it 'creates a visit with correct attributes' do
        service.call
        visit = service.visit

        expect(visit.name).to eq('Test Visit')
        expect(visit.user).to eq(user)
        expect(visit.status).to eq('confirmed')
        expect(visit.started_at).to eq(DateTime.parse('2023-12-01T10:00:00Z'))
        expect(visit.ended_at).to eq(DateTime.parse('2023-12-01T12:00:00Z'))
        expect(visit.duration).to eq(120) # 2 hours in minutes
      end

      it 'creates a place with correct coordinates' do
        service.call
        place = service.visit.place

        expect(place).to be_persisted
        expect(place.name).to eq('Test Visit')
        expect(place.latitude).to eq(52.52)
        expect(place.longitude).to eq(13.405)
        expect(place.source).to eq('manual')
      end
    end

    context 'when reusing existing place' do
      let!(:existing_place) do
        create(:place,
               user: user,
               latitude: 52.52,
               longitude: 13.405,
               lonlat: 'POINT(13.405 52.52)')
      end
      let!(:existing_visit) { create(:visit, user: user, place: existing_place) }

      subject(:service) { described_class.new(user, valid_params) }

      it 'reuses the existing place' do
        expect { service.call }.not_to(change { Place.count })
        expect(service.visit.place).to eq(existing_place)
      end

      it 'creates a new visit with the existing place' do
        expect { service.call }.to change { user.visits.count }.by(1)
        expect(service.visit.place).to eq(existing_place)
      end
    end

    context 'IDOR — cross-user place leak' do
      let(:user_a) { create(:user) }
      let(:user_b) { create(:user) }

      let!(:user_a_place) do
        create(:place,
               user: user_a,
               name: "User A's Place",
               latitude: 52.52,
               longitude: 13.405,
               lonlat: 'POINT(13.405 52.52)')
      end

      let!(:user_b_existing_visit_with_user_a_place) do
        create(:visit, user: user_b, place: user_a_place,
                       started_at: Time.zone.parse('2023-11-01T10:00:00Z'),
                       ended_at: Time.zone.parse('2023-11-01T11:00:00Z'))
      end

      let(:user_b_params) do
        {
          name: "User B's New Visit",
          latitude: 52.52,
          longitude: 13.405,
          started_at: '2023-12-01T10:00:00Z',
          ended_at: '2023-12-01T12:00:00Z'
        }
      end

      subject(:service) { described_class.new(user_b, user_b_params) }

      it "does not attach user A's place to user B's new visit" do
        service.call
        new_visit = user_b.visits
                          .where(started_at: Time.zone.parse('2023-12-01T10:00:00Z'))
                          .first

        expect(new_visit).to be_present
        expect(new_visit.place_id).not_to eq(user_a_place.id)
        expect(new_visit.place.user_id).to eq(user_b.id) if new_visit.place
      end

      it 'creates a fresh place owned by user B at the requested coordinates' do
        expect { service.call }.to change { user_b.places.count }.by(1)

        new_place = user_b.places.last
        expect(new_place.user_id).to eq(user_b.id)
        expect(new_place.latitude).to eq(52.52)
        expect(new_place.longitude).to eq(13.405)
      end
    end

    context 'distance threshold is exactly 100 meters (no degree-vs-meter drift)' do
      let(:base_lat) { 52.52 }
      let(:base_lon) { 13.405 }

      let!(:existing_place) do
        create(:place,
               user: user,
               latitude: base_lat,
               longitude: base_lon,
               lonlat: "POINT(#{base_lon} #{base_lat})")
      end
      let!(:existing_visit) { create(:visit, user: user, place: existing_place) }

      let(:lon_offset_120m) { 0.0018 }

      it 'does NOT match a place 120m away (would have matched under the old 0.001° threshold)' do
        params_120m_away = valid_params.merge(
          latitude: base_lat,
          longitude: base_lon + lon_offset_120m
        )

        service = described_class.new(user, params_120m_away)
        expect { service.call }.to change { Place.count }.by(1)
        expect(service.visit.place).not_to eq(existing_place)
      end

      it 'matches a place 50m away' do
        params_50m_away = valid_params.merge(
          latitude: base_lat,
          longitude: base_lon + 0.0006
        )

        service = described_class.new(user, params_50m_away)
        expect { service.call }.not_to(change { Place.count })
        expect(service.visit.place).to eq(existing_place)
      end
    end

    context 'place name locking' do
      it 'locks the place name when the visit is confirmed' do
        service = described_class.new(user, valid_params)
        service.call

        expect(service.visit.place.name_locked_at).to be_present
      end

      it 'leaves the place name unlocked when the visit is suggested' do
        service = described_class.new(user, valid_params.merge(status: 'suggested'))
        service.call

        expect(service.visit.place.name_locked_at).to be_nil
      end

      it 'lets reverse geocoding rename a place created from a suggested visit' do
        service = described_class.new(user, valid_params.merge(status: 'suggested'))
        service.call
        place = service.visit.place

        expect(place.name_locked?).to be(false)
      end
    end

    context 'geocoding a machine-named place' do
      before { allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true) }

      it 'enqueues Places::NameFetchingJob for a place created from a suggested visit' do
        service = described_class.new(user, valid_params.merge(status: 'suggested'))

        expect { service.call }.to have_enqueued_job(Places::NameFetchingJob).with(an_instance_of(Integer))
      end

      it 'does not enqueue for a confirmed visit, whose name the user asserted' do
        service = described_class.new(user, valid_params)

        expect { service.call }.not_to have_enqueued_job(Places::NameFetchingJob)
      end

      it 'does not enqueue when an existing place is reused' do
        existing = create(:place, user: user, latitude: 52.52, longitude: 13.405, lonlat: 'POINT(13.405 52.52)')
        create(:visit, user: user, place: existing)
        service = described_class.new(user, valid_params.merge(status: 'suggested'))

        expect { service.call }.not_to have_enqueued_job(Places::NameFetchingJob)
      end

      it 'does not enqueue when reverse geocoding is disabled' do
        allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
        service = described_class.new(user, valid_params.merge(status: 'suggested'))

        expect { service.call }.not_to have_enqueued_job(Places::NameFetchingJob)
      end

      it 'does not enqueue for a place the rolled-back transaction discarded' do
        visits_association = user.visits
        allow(user).to receive(:visits).and_return(visits_association)
        allow(visits_association).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Visit.new))
        service = described_class.new(user, valid_params.merge(status: 'suggested'))

        expect { service.call }.not_to have_enqueued_job(Places::NameFetchingJob)
      end
    end

    context 'when timestamps are unusable' do
      it 'fails cleanly on an unparseable started_at instead of raising' do
        service = described_class.new(user, valid_params.merge(started_at: 'not-a-timestamp'))

        expect(service.call).to be(false)
        expect(service.errors).to be_present
      end

      it 'fails cleanly on a missing ended_at' do
        service = described_class.new(user, valid_params.merge(ended_at: nil))

        expect(service.call).to be(false)
      end

      it 'does not report an exception for a malformed timestamp' do
        expect(ExceptionReporter).not_to receive(:call)

        described_class.new(user, valid_params.merge(started_at: 'garbage')).call
      end

      it 'does not create a visit when timestamps are unusable' do
        expect do
          described_class.new(user, valid_params.merge(started_at: 'garbage')).call
        end.not_to(change { Visit.count })
      end
    end

    context 'reporting whether the visit was newly created' do
      it 'is not a duplicate on first creation' do
        service = described_class.new(user, valid_params)
        service.call

        expect(service).not_to be_duplicate
      end

      it 'flags a replayed visit as a duplicate' do
        described_class.new(user, valid_params).call

        service = described_class.new(user, valid_params)
        service.call

        expect(service).to be_duplicate
      end
    end

    context 'when the place name fetch cannot be enqueued' do
      before do
        allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
        allow(Places::NameFetchingJob).to receive(:perform_later).and_raise(RedisClient::ConnectionError)
      end

      it 'still reports the committed visit as created' do
        service = described_class.new(user, valid_params.merge(status: 'suggested'))

        expect(service.call).to be_truthy
        expect(service.visit).to be_persisted
      end

      it 'keeps the visit even though the job could not be queued' do
        service = described_class.new(user, valid_params.merge(status: 'suggested'))

        expect { service.call }.to change { user.visits.count }.by(1)
      end
    end

    context 'when coordinates are unusable' do
      it 'refuses a missing latitude instead of creating a place at Null Island' do
        service = described_class.new(user, valid_params.merge(latitude: nil))

        expect(service.call).to be(false)
        expect(service.errors).to be_present
      end

      it 'refuses a non-numeric longitude' do
        service = described_class.new(user, valid_params.merge(longitude: 'east'))

        expect(service.call).to be(false)
      end

      it 'refuses an out-of-range latitude' do
        service = described_class.new(user, valid_params.merge(latitude: 91.0))

        expect(service.call).to be(false)
      end

      it 'creates no place when coordinates are unusable' do
        expect do
          described_class.new(user, valid_params.merge(latitude: nil)).call
        end.not_to(change { Place.count })
      end
    end

    context 'when a machine retry replays a visit the user removed' do
      let(:suggested_params) { valid_params.merge(status: 'suggested') }

      it 'does not resurrect a visit the user deleted' do
        first = described_class.new(user, suggested_params)
        first.call
        first.visit.soft_delete!

        service = described_class.new(user, suggested_params)
        service.call

        expect(first.visit.reload.deleted_at).to be_present
      end

      it 'does not un-decline a visit the user declined' do
        first = described_class.new(user, suggested_params)
        first.call
        first.visit.update!(status: :declined)

        service = described_class.new(user, suggested_params)
        service.call

        expect(first.visit.reload.status).to eq('declined')
      end

      it 'still resurrects when a person re-creates the visit explicitly' do
        first = described_class.new(user, valid_params)
        first.call
        first.visit.soft_delete!

        service = described_class.new(user, valid_params)
        service.call

        expect(first.visit.reload.deleted_at).to be_nil
      end
    end

    context 'when place creation fails' do
      subject(:service) { described_class.new(user, valid_params) }

      before do
        allow(Place).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Place.new))
      end

      it 'returns false' do
        expect(service.call).to be(false)
      end

      it 'calls ExceptionReporter' do
        expect(ExceptionReporter).to receive(:call)

        service.call
      end

      it 'does not create a visit' do
        expect { service.call }.not_to(change { Visit.count })
      end
    end

    context 'when visit creation fails' do
      subject(:service) { described_class.new(user, valid_params) }

      before do
        visits_association = user.visits
        allow(user).to receive(:visits).and_return(visits_association)
        allow(visits_association).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Visit.new))
      end

      it 'returns false' do
        expect(service.call).to be(false)
      end

      it 'calls ExceptionReporter' do
        expect(ExceptionReporter).to receive(:call)

        service.call
      end
    end

    describe 'no suggested_places attachment on manual visit creation' do
      let(:user)  { create(:user) }
      let(:place) { create(:place, user: user, latitude: 52.5126, longitude: 13.4012) }
      let(:other) { create(:place, user: user, latitude: 52.5127, longitude: 13.4013) }

      it 'does not create PlaceVisit rows when API creates a visit' do
        place
        other
        params = {
          latitude: 52.5126, longitude: 13.4012,
          name: 'Test', started_at: 1.hour.ago.iso8601, ended_at: Time.current.iso8601,
          status: 'suggested'
        }

        expect { described_class.new(user, params).call }.not_to(change { PlaceVisit.count })
      end
    end

    context 'edge cases' do
      context 'when name is not provided but defaults are used' do
        let(:params) { valid_params.merge(name: '') }
        subject(:service) { described_class.new(user, params) }

        it 'returns false due to validation' do
          expect(service.call).to be(false)
        end
      end

      context 'when coordinates are strings' do
        let(:params) do
          valid_params.merge(
            latitude: '52.52',
            longitude: '13.405'
          )
        end
        subject(:service) { described_class.new(user, params) }

        it 'converts them to floats and creates visit successfully' do
          expect(service.call).to be_truthy
          place = service.visit.place
          expect(place.latitude).to eq(52.52)
          expect(place.longitude).to eq(13.405)
        end
      end

      context 'when visit duration is very short' do
        let(:params) do
          valid_params.merge(
            started_at: '2023-12-01T12:00:00Z',
            ended_at: '2023-12-01T12:01:00Z' # 1 minute
          )
        end
        subject(:service) { described_class.new(user, params) }

        it 'creates visit with correct duration' do
          service.call
          expect(service.visit.duration).to eq(1)
        end
      end

      context 'when visit duration is very long' do
        let(:params) do
          valid_params.merge(
            started_at: '2023-12-01T08:00:00Z',
            ended_at: '2023-12-02T20:00:00Z' # 36 hours
          )
        end
        subject(:service) { described_class.new(user, params) }

        it 'creates visit with correct duration' do
          service.call
          expect(service.visit.duration).to eq(36 * 60) # 36 hours in minutes
        end
      end

      context 'when datetime-local input is provided without timezone' do
        let(:params) do
          valid_params.merge(
            started_at: '2023-12-01T19:54',
            ended_at: '2023-12-01T20:54'
          )
        end
        subject(:service) { described_class.new(user, params) }

        it 'parses the datetime in the application timezone' do
          service.call
          visit = service.visit

          expect(visit.started_at.hour).to eq(19)
          expect(visit.started_at.min).to eq(54)
          expect(visit.ended_at.hour).to eq(20)
          expect(visit.ended_at.min).to eq(54)
        end

        it 'calculates correct duration' do
          service.call
          expect(service.visit.duration).to eq(60) # 1 hour in minutes
        end
      end
    end
  end
end
