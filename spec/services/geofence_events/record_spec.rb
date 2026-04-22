# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GeofenceEvents::Record do
  let(:user) { create(:user) }
  let(:area) { create(:area, user: user) }
  let(:base_attrs) do
    {
      user: user,
      area: area,
      event_type: :enter,
      source: :server_inferred,
      occurred_at: Time.current,
      lonlat: 'POINT(13.4 52.5)',
      accuracy_m: 25
    }
  end

  before { GeofenceEvents::Evaluator::StateStore.reset!(user) }

  describe '.call' do
    it 'creates a GeofenceEvent' do
      expect { described_class.call(**base_attrs) }.to change(GeofenceEvent, :count).by(1)
    end

    it 'updates StateStore on enter' do
      described_class.call(**base_attrs)
      expect(GeofenceEvents::Evaluator::StateStore.currently_inside(user)).to include(area.id)
    end

    it 'updates StateStore on leave' do
      described_class.call(**base_attrs)
      described_class.call(**base_attrs.merge(event_type: :leave))
      expect(GeofenceEvents::Evaluator::StateStore.currently_inside(user)).not_to include(area.id)
    end

    context 'with a subscribed webhook' do
      let!(:webhook) { create(:webhook, user: user, area_ids: [], event_types: [0]) }

      it 'creates a WebhookDelivery' do
        expect { described_class.call(**base_attrs) }.to change(WebhookDelivery, :count).by(1)
      end

      it 'enqueues Webhooks::DeliverJob' do
        expect { described_class.call(**base_attrs) }
          .to have_enqueued_job(Webhooks::DeliverJob)
      end
    end

    context 'with an inactive webhook' do
      let!(:webhook) { create(:webhook, user: user, active: false) }

      it 'does not create a delivery' do
        expect { described_class.call(**base_attrs) }.not_to change(WebhookDelivery, :count)
      end
    end

    context 'within the dedup window (120s)' do
      let!(:webhook) { create(:webhook, user: user) }

      it 'persists the event but skips webhook delivery' do
        described_class.call(**base_attrs)
        expect do
          described_class.call(**base_attrs.merge(occurred_at: 60.seconds.from_now))
        end.to change(GeofenceEvent, :count).by(1)
           .and(change(WebhookDelivery, :count).by(0))
      end
    end

    context 'outside the dedup window' do
      let!(:webhook) { create(:webhook, user: user) }

      it 'delivers the webhook' do
        described_class.call(**base_attrs)
        expect do
          described_class.call(**base_attrs.merge(occurred_at: 130.seconds.from_now))
        end.to change(WebhookDelivery, :count).by(1)
      end
    end

    context 'when Redis is unavailable' do
      let!(:webhook) { create(:webhook, user: user) }

      before do
        allow(GeofenceEvents::Evaluator::StateStore).to receive(:apply)
          .and_raise(Redis::CannotConnectError)
      end

      it 'still persists the event' do
        expect { described_class.call(**base_attrs) }.to change(GeofenceEvent, :count).by(1)
      end

      it 'still enqueues webhook delivery' do
        expect { described_class.call(**base_attrs) }.to change(WebhookDelivery, :count).by(1)
      end

      it 'reports the error to Sentry' do
        expect(Sentry).to receive(:capture_exception).with(
          instance_of(Redis::CannotConnectError),
          hash_including(extra: hash_including(:user_id))
        )
        described_class.call(**base_attrs)
      end
    end
  end
end
