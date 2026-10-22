# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Cached point pagination', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:timestamp) { 1.day.ago.to_i }

  before do
    Point.insert_all!(51.times.map do |index|
      { user_id: user.id, timestamp: timestamp + index, lonlat: 'POINT(13 52)' }
    end)
  end

  def count_queries(&block)
    statements = []
    ActiveSupport::Notifications.subscribed(->(*args) { statements << args.last[:sql] }, 'sql.active_record', &block)
    statements.grep(/SELECT.*COUNT\(\*\).*FROM "points"/i)
  end

  it 'reuses the page count across pages while retaining the exact entry summary' do
    sign_in user
    get points_url
    expect(response).to have_http_status(:ok)
    expect(count_queries { get points_url(page: 2) }).to be_empty
    expect(response.body).to include('51')
    user.points.order(:id).last.destroy!
    get points_url(page: 1)
    expect(response.body).to include('50')
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    user.update_column(:plan, User.plans[:lite])
    user.points.update_all('timestamp = timestamp - 63072000')
    get points_url(start_at: 3.years.ago.to_i)
    expect(response).to have_http_status(:ok)
  end

  it 'reuses API totals across pages and default end times and invalidates on bulk writes' do
    get api_v1_points_url(api_key: user.api_key, per_page: 50)
    expect(response.headers['X-Total-Pages']).to eq('2')
    travel 2.seconds do
      expect(count_queries { get api_v1_points_url(api_key: user.api_key, per_page: 50, page: 2) }).to be_empty
      expect(response.headers['X-Current-Page']).to eq('2')
      expect(response.parsed_body.size).to eq(1)
    end
    user.points.where(timestamp: timestamp + 50).delete_all
    get api_v1_points_url(api_key: user.api_key, per_page: 50)
    expect(response.headers['X-Total-Pages']).to eq('1')
    expect(response.parsed_body.size).to eq(50)
    Point.insert_all!([{ user_id: user.id, timestamp: -10, lonlat: 'POINT(1 1)' }])
    user.update!(settings: user.settings.merge('timezone' => 'Europe/Berlin'))
    get api_v1_points_url(api_key: user.api_key, end_at: '1970-01-01')
    expect(response.parsed_body).to eq([])
    expect(response.headers['X-Total-Pages']).to eq('0')
  end

  it 'reuses Lite totals across sliding cutoffs and still tracks scoped membership changes' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    user.update_column(:plan, User.plans[:lite])
    get api_v1_points_url(api_key: user.api_key, per_page: 50)
    expect(response.headers['X-Scoped-Points']).to eq('51')
    travel 2.seconds do
      expect(count_queries { get api_v1_points_url(api_key: user.api_key, per_page: 50, page: 2) }).to be_empty
      expect(response.headers['X-Total-Points-In-Range']).to eq('51')
    end
    user.points.where(timestamp: timestamp + 50).update_all(timestamp: 2.years.ago.to_i)
    get api_v1_points_url(api_key: user.api_key, per_page: 50)
    expect(response.headers['X-Scoped-Points']).to eq('50')
    expect(response.headers['X-Total-Points-In-Range']).to eq('51')
  end
end
