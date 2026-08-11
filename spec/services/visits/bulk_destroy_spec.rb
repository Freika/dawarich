# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::BulkDestroy do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }

  let!(:visit1) { create(:visit, user: user) }
  let!(:visit2) { create(:visit, user: user) }
  let!(:visit3) { create(:visit, user: user) }
  let!(:other_user_visit) { create(:visit, user: other_user) }

  describe '#call' do
    context 'when given valid visit ids' do
      let(:visit_ids) { [visit1.id, visit2.id] }
      subject(:service) { described_class.new(user, visit_ids) }

      it 'soft-deletes the specified visits, keeping tombstones' do
        result = service.call

        expect(result[:count]).to eq(2)
        expect(Visit.active.where(id: visit_ids)).to be_empty
        expect(Visit.where(id: visit_ids).pluck(:deleted_at)).to all(be_present)
        expect(Visit.active.where(id: visit3.id)).to exist
      end

      it 'enqueues orphan-place checks for the affected places' do
        place = create(:place, user: user, source: :photon)
        visit_with_place = create(:visit, user: user, place: place, area: nil)

        expect { described_class.new(user, [visit_with_place.id]).call }
          .to have_enqueued_job(Places::DeleteIfOrphanJob).with(place.id)
      end

      it 'leaves other users\' visits untouched' do
        service.call

        expect(other_user_visit.reload.deleted_at).to be_nil
      end

      it 'returns the started_ats of removed visits' do
        result = service.call

        expect(result[:started_ats]).to contain_exactly(visit1.started_at, visit2.started_at)
      end
    end

    context 'when an id belongs to another user' do
      let(:visit_ids) { [visit1.id, other_user_visit.id] }
      subject(:service) { described_class.new(user, visit_ids) }

      it 'soft-deletes only the user\'s own visits' do
        result = service.call

        expect(result[:count]).to eq(1)
        expect(visit1.reload.deleted_at).to be_present
        expect(other_user_visit.reload.deleted_at).to be_nil
      end
    end

    context 'plan-tier scoping' do
      it 'refuses to remove visits outside the Lite data window' do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        user.update!(plan: :lite)
        old_visit = create(:visit, user: user, started_at: 13.months.ago, ended_at: 13.months.ago + 30.minutes)

        result = described_class.new(user, [old_visit.id]).call

        expect(result).to be(false)
        expect(old_visit.reload.deleted_at).to be_nil
      end
    end

    context 'when visit_ids is blank' do
      subject(:service) { described_class.new(user, []) }

      it 'returns false and records an error' do
        expect(service.call).to be(false)
        expect(service.errors).to include('No visits selected')
      end
    end

    context 'when visit_ids exceeds the maximum batch size' do
      subject(:service) { described_class.new(user, (1..(described_class::MAX_VISIT_IDS + 1)).to_a) }

      it 'returns false and records an error' do
        expect(service.call).to be(false)
        expect(service.errors.first).to match(/Too many visits/i)
      end
    end

    context 'when visit_ids matches no rows' do
      subject(:service) { described_class.new(user, [-1, -2]) }

      it 'returns false and records an error' do
        expect(service.call).to be(false)
        expect(service.errors).to include('No matching visits found')
      end
    end

    context 'when the bulk update raises' do
      subject(:service) { described_class.new(user, [visit1.id, visit2.id]) }

      it 'reports an error and leaves the visits visible' do
        allow_any_instance_of(ActiveRecord::Relation)
          .to receive(:update_all).and_raise(ActiveRecord::StatementInvalid)

        expect(service.call).to be(false)
        expect(service.errors).to include(/database error/i)
        expect(Visit.active.where(id: [visit1.id, visit2.id]).count).to eq(2)
      end
    end

    context 'points and place links' do
      let!(:place) { create(:place) }
      let!(:place_visit) { create(:place_visit, visit: visit1, place: place) }
      let!(:point) { create(:point, user: user, visit: visit1) }
      subject(:service) { described_class.new(user, [visit1.id]) }

      it 'keeps points and place_visits attached to the tombstone' do
        expect { service.call }.not_to change(Point, :count)

        expect(point.reload.visit_id).to eq(visit1.id)
        expect(PlaceVisit.where(id: place_visit.id)).to exist
        expect(Place.where(id: place.id)).to exist
      end
    end

    context 'when many visits are selected' do
      let!(:many_visits) { create_list(:visit, 60, user: user) }
      subject(:service) { described_class.new(user, many_visits.map(&:id)) }

      it 'soft-deletes every visit in one pass' do
        result = service.call

        expect(result[:count]).to eq(60)
        expect(Visit.active.where(id: many_visits.map(&:id))).to be_empty
        expect(Visit.where(id: many_visits.map(&:id)).pluck(:deleted_at)).to all(be_present)
      end
    end
  end
end
