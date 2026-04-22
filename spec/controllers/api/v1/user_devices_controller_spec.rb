# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::UserDevicesController, type: :controller do
  let(:user) { create(:user) }

  before { request.headers.merge!('Authorization' => "Bearer #{user.api_key}") }

  describe 'POST #create' do
    it 'registers a new device' do
      post :create, params: {
        user_device: { platform: 'ios', device_id: 'abc', device_name: 'iPhone',
                       push_token: 'tok', app_version: '1.0.0' }
      }
      expect(response).to have_http_status(:created)
      expect(user.user_devices.count).to eq(1)
    end

    it 'updates on duplicate device_id (upsert behavior)' do
      create(:user_device, user: user, device_id: 'abc', push_token: 'old')
      post :create, params: {
        user_device: { platform: 'ios', device_id: 'abc', push_token: 'new' }
      }
      expect(response).to have_http_status(:ok)
      expect(user.user_devices.find_by(device_id: 'abc').push_token).to eq('new')
    end
  end

  describe 'GET #index' do
    it 'lists current user devices' do
      create(:user_device, user: user)
      get :index
      expect(JSON.parse(response.body).length).to eq(1)
    end
  end

  describe 'DELETE #destroy' do
    it 'revokes the device' do
      device = create(:user_device, user: user)
      delete :destroy, params: { id: device.id }
      expect(response).to have_http_status(:no_content)
      expect(UserDevice.find_by(id: device.id)).to be_nil
    end
  end
end
