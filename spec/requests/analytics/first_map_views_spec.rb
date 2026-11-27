# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /analytics/first_map_view', type: :request do
  let(:user) { create(:user) }
  let(:import) { create(:import, user:, status: :completed) }
  let(:viewed_at) { Time.zone.parse('2026-03-15 12:00') }
  let(:period) { { start_at: '2026-03-01T00:00:00Z', end_at: '2026-03-31T23:59:59Z' } }

  def post_view(params = period)
    post analytics_first_map_view_path, params:, as: :json
    response.parsed_body['status']
  end

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    sign_in user
  end

  it 'records the first view of a period that holds imported points' do
    create(:point, user:, import:, timestamp: viewed_at.to_i)

    expect(post_view).to eq('recorded')
    expect(AnalyticsEvent.sole).to have_attributes(event: 'first_map_data_viewed', user_id: user.id)
  end

  it 'records the view once per account' do
    create(:point, user:, import:, timestamp: viewed_at.to_i)
    post_view

    expect(post_view).to eq('already_recorded')
    expect(AnalyticsEvent.count).to eq(1)
  end

  it 'does not count a period with only tracker points' do
    create(:point, user:, import: nil, timestamp: viewed_at.to_i)

    expect(post_view).to eq('no_imported_data')
    expect(AnalyticsEvent.count).to eq(0)
  end

  it 'does not count imported points outside the period' do
    create(:point, user:, import:, timestamp: (viewed_at + 2.months).to_i)

    expect(post_view).to eq('no_imported_data')
  end

  it 'does not count the demo data' do
    demo = create(:import, user:, status: :completed, demo: true)
    create(:point, user:, import: demo, timestamp: viewed_at.to_i)

    expect(post_view).to eq('no_imported_data')
  end

  it 'does not count another user’s imported points' do
    other = create(:user)
    create(:point, user: other, import: create(:import, user: other), timestamp: viewed_at.to_i)

    expect(post_view).to eq('no_imported_data')
  end

  it 'does not count imported points a Lite user cannot see' do
    lite = create(:user, :lite_plan)
    old_import = create(:import, user: lite, status: :completed)
    create(:point, user: lite, import: old_import, timestamp: 2.years.ago.to_i)
    sign_in lite

    expect(post_view(start_at: 3.years.ago.iso8601, end_at: Time.current.iso8601)).to eq('no_imported_data')
  end

  it 'rejects a request without a valid period' do
    post analytics_first_map_view_path, params: { start_at: 'nope' }, as: :json

    expect(response).to have_http_status(:bad_request)
  end

  it 'is not available on self-hosted instances' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

    post analytics_first_map_view_path, params: period, as: :json

    expect(response).to have_http_status(:not_found)
  end
end
