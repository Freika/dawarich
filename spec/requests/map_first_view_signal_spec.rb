# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'First map view signal on the map page', type: :request do
  let(:user) { create(:user, settings: { 'onboarding_completed' => true }) }

  def signal
    Nokogiri::HTML(response.body).at_css('[data-controller="first-map-view"]')
  end

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    sign_in user
  end

  it 'listens for loaded periods when the user has imported data' do
    create(:import, user:)

    get map_v2_path

    expect(signal['data-first-map-view-url-value']).to eq('/analytics/first_map_view')
  end

  it 'is absent before the first import' do
    get map_v2_path

    expect(signal).to be_nil
  end

  it 'is absent once the first view was recorded' do
    create(:import, user:)
    AnalyticsEvent.record(user:, event: :first_map_data_viewed, dedup_key: "first_map_data_viewed:#{user.id}")

    get map_v2_path

    expect(signal).to be_nil
  end
end
