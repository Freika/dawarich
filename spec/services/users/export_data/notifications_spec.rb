# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::ExportData::Notifications, type: :service do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user) }

  describe '#call' do
    context 'when user has no notifications' do
      it 'returns an empty array' do
        result = service.call
        expect(result).to eq([])
      end
    end

    context 'when user has notifications' do
      let!(:notification1) { create(:notification, user: user, title: 'Test 1', kind: :info) }
      let!(:notification2) { create(:notification, user: user, title: 'Test 2', kind: :warning) }

      it 'returns all user notifications' do
        result = service.call
        expect(result).to be_an(Array)
        expect(result.size).to eq(2)
      end

      it 'excludes user_id and id fields' do
        result = service.call

        result.each do |notification_data|
          expect(notification_data).not_to have_key('user_id')
          expect(notification_data).not_to have_key('id')
        end
      end

      it 'includes expected notification attributes' do
        result = service.call
        notification_data = result.find { |n| n['title'] == 'Test 1' }

        expect(notification_data).to include(
          'title' => 'Test 1',
          'kind' => 'info'
        )
        expect(notification_data).to have_key('created_at')
        expect(notification_data).to have_key('updated_at')
      end
    end

    context 'with multiple users' do
      let(:other_user) { create(:user) }
      let!(:user_notification) { create(:notification, user: user, title: 'User Notification') }
      let!(:other_user_notification) { create(:notification, user: other_user, title: 'Other Notification') }

      it 'only returns notifications for the specified user' do
        result = service.call
        expect(result.size).to eq(1)
        expect(result.first['title']).to eq('User Notification')
      end
    end
  end
end
