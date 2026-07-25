# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Shared link expiry dates', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }

  before { sign_in user }

  it 'expires a live share at the start of the selected date in the user timezone' do
    travel_to Time.zone.parse('2026-07-14 12:00:00 UTC') do
      post share_links_live_path, params: {
        shared_link: { expires_at: '2026-07-16' }
      }

      expect(response).to redirect_to(new_share_links_live_path)
      expect(user.shared_links.last.expires_at).to eq(Time.find_zone!('Europe/Berlin').local(2026, 7, 16))
    end
  end
end
