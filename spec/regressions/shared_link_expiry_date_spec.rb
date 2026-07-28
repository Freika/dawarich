# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Shared link expiry dates', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:zone) { Time.find_zone!('Pacific/Auckland') }
  let(:user) do
    create(:user).tap { |u| u.update!(settings: u.settings.to_h.merge('timezone' => 'Pacific/Auckland')) }
  end
  let(:creation_moment) { Time.utc(2026, 7, 14, 12, 0, 0) }

  before { sign_in user }

  def latest_expiry_for(resource_type)
    user.shared_links.where(resource_type: resource_type).last.expires_at
  end

  it 'expires a live share at the start of the selected date in the owner timezone, not config.time_zone' do
    travel_to creation_moment do
      post share_links_live_path, params: { shared_link: { expires_at: '2026-07-16' } }

      expect(response).to redirect_to(new_share_links_live_path)
      expect(latest_expiry_for(:live)).to eq(zone.local(2026, 7, 16))
    end
  end

  it 'stops serving the share once the selected date begins' do
    link = travel_to(creation_moment) do
      post share_links_live_path, params: { shared_link: { expires_at: '2026-07-16' } }
      user.shared_links.last
    end

    travel_to(zone.local(2026, 7, 15, 23, 59, 0)) { expect(link.reload).to be_active }
    travel_to(zone.local(2026, 7, 16, 0, 0, 1)) { expect(link.reload).not_to be_active }
  end

  it 'applies the same conversion to trip, track and timeline shares' do
    trip  = create(:trip, user: user)
    track = create(:track, user: user)

    travel_to creation_moment do
      post trip_share_link_path(trip),   params: { shared_link: { expires_at: '2026-07-16' } }
      post track_share_link_path(track), params: { shared_link: { expires_at: '2026-07-16' } }
      post share_links_timeline_path, params: {
        shared_link: { start_date: '2026-07-01', end_date: '2026-07-10', expires_at: '2026-07-16' }
      }

      expect(latest_expiry_for(:trip)).to eq(zone.local(2026, 7, 16))
      expect(latest_expiry_for(:track)).to eq(zone.local(2026, 7, 16))
      expect(latest_expiry_for(:timeline)).to eq(zone.local(2026, 7, 16))
    end
  end

  it 'states the expiry semantics on every share modal' do
    trip  = create(:trip, user: user)
    track = create(:track, user: user)

    [new_share_links_live_path, new_share_links_timeline_path,
     new_trip_share_link_path(trip), new_track_share_link_path(track)].each do |path|
      get path

      expect(response.body).to include('through the end of the day before the selected date')
    end
  end

  it 'leaves the link permanent when no expiry date is given' do
    travel_to creation_moment do
      post share_links_live_path, params: { shared_link: { expires_at: '' } }

      expect(latest_expiry_for(:live)).to be_nil
    end
  end
end
