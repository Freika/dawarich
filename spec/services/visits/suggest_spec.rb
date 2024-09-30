# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Suggest do
  describe '#call' do
    let!(:user) { create(:user) }
    let(:start_at) { 1.week.ago }
    let(:end_at) { Time.current }

    let!(:points) do
      [
        create(:point, :with_known_location, user:, timestamp: start_at),
        create(:point, :with_known_location, user:, timestamp: start_at + 5.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 10.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 15.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 20.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 25.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 30.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 35.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 40.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 45.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 50.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 55.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 95.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 100.minutes),
        create(:point, :with_known_location, user:, timestamp: start_at + 105.minutes)
      ]
    end

    subject { described_class.new(user, start_at:, end_at:).call }

    it 'creates places' do
      expect { subject }.to change(Place, :count).by(1)
    end

    it 'creates visits' do
      expect { subject }.to change(Visit, :count).by(1)
    end

    it 'creates visits notification' do
      expect { subject }.to change(Notification, :count).by(1)
    end

    it 'reverse geocodes visits' do
      expect_any_instance_of(Visit).to receive(:async_reverse_geocode).and_call_original

      subject
    end

    context 'when reverse geocoding is enabled' do
      before do
        stub_const('REVERSE_GEOCODING_ENABLED', true)
        stub_const('PHOTON_API_HOST', 'http://localhost:2323')
      end

      it 'reverse geocodes visits' do
        expect_any_instance_of(Visit).to receive(:async_reverse_geocode).and_call_original

        subject
      end
    end
  end
end
