# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::CreateLocationRequest do
  include ActiveSupport::Testing::TimeHelpers

  let(:family) { create(:family) }
  let(:requester) { family.creator }
  let(:target_user) { create(:user) }

  before do
    create(:family_membership, family: family, user: requester, role: :owner)
    create(:family_membership, family: family, user: target_user)
  end

  describe '#call' do
    subject(:result) { described_class.new(requester: requester, target_user: target_user).call }

    context 'when valid' do
      it 'creates a location request' do
        expect { result }.to change(Family::LocationRequest, :count).by(1)
        expect(result.success?).to be true
      end

      it 'creates request with correct attributes' do
        result
        request = Family::LocationRequest.last
        expect(request.requester).to eq(requester)
        expect(request.target_user).to eq(target_user)
        expect(request.family).to eq(family)
        expect(request).to be_pending
      end

      it 'creates an in-app notification for the target user' do
        expect { result }.to change { Notification.where(user: target_user).count }.by(1)
      end

      it 'creates notification with XSS-safe content' do
        result
        notification = Notification.where(user: target_user).last
        expect(notification.title).to eq('Location Request')
        expect(notification.content).not_to include('<script>')
      end

      it 'enqueues an email' do
        expect { result }.to have_enqueued_mail(FamilyMailer, :location_request)
      end
    end

    context 'when requester and target are the same user' do
      subject(:result) { described_class.new(requester: requester, target_user: requester).call }

      it 'returns failure' do
        expect(result.success?).to be false
        expect(result.status).to eq(:unprocessable_content)
      end
    end

    context 'when users are not in the same family' do
      let(:outsider) { create(:user) }

      subject(:result) { described_class.new(requester: requester, target_user: outsider).call }

      it 'returns failure' do
        expect(result.success?).to be false
        expect(result.payload[:message]).to include('same family')
      end
    end

    context 'when target user is already sharing location' do
      before { target_user.update_family_location_sharing!(true, duration: 'permanent') }

      it 'returns failure' do
        expect(result.success?).to be false
        expect(result.payload[:message]).to include('already sharing')
      end
    end

    context 'when cooldown is active' do
      before do
        create(:family_location_request,
               requester: requester, target_user: target_user, family: family,
               status: :pending, created_at: 30.minutes.ago)
      end

      it 'returns failure' do
        expect(result.success?).to be false
        expect(result.payload[:message]).to include('cooldown')
      end
    end

    context 'when previous request was more than 1 hour ago' do
      before do
        create(:family_location_request,
               requester: requester, target_user: target_user, family: family,
               status: :pending, created_at: 2.hours.ago)
      end

      it 'succeeds' do
        expect(result.success?).to be true
      end
    end

    context 'when previous request is expired (not pending)' do
      before do
        create(:family_location_request,
               requester: requester, target_user: target_user, family: family,
               status: :expired, created_at: 30.minutes.ago)
      end

      it 'succeeds (expired requests do not count toward cooldown)' do
        expect(result.success?).to be true
      end
    end
  end
end
