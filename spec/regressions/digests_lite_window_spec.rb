# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Digest generation data window', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

  around { |example| travel_to(Time.utc(2026, 9, 6, 12)) { example.run } }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    user.update_columns(plan: User.plans[:lite], status: User.statuses[:active], active_until: 1.year.from_now)
    create(:stat, user: user, year: 2023, month: 1)
    create(:stat, user: user, year: 2025, month: 10)
    sign_in user
  end

  it 'does not offer an inaccessible year in the web generation menu' do
    get users_digests_path

    expect(response).to have_http_status(:ok)
    links = Nokogiri::HTML(response.body).css('a[data-turbo-method="post"]').map(&:text)
    expect(links).not_to include('2023')
    expect(links).to include('2025')
  end

  it 'does not offer an inaccessible year in the API' do
    get api_v1_digests_path, headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['availableYears']).to eq([2025])
  end

  it 'rejects a web request for an inaccessible year without queuing a doomed job' do
    expect do
      post users_digests_path, params: { year: 2023 }
    end.not_to have_enqueued_job(Users::Digests::Yearly::CalculatingJob)
    expect(flash[:alert]).to be_present
    expect(flash[:notice]).to be_nil
  end

  it 'rejects an API request for an inaccessible year without queuing a doomed job' do
    expect do
      post api_v1_digests_path, params: { year: 2023 }, headers: headers
    end.not_to have_enqueued_job(Users::Digests::Yearly::CalculatingJob)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'still accepts a year with accessible stats from the web' do
    expect do
      post users_digests_path, params: { year: 2025 }
    end.to have_enqueued_job(Users::Digests::Yearly::CalculatingJob).with(user.id, 2025)
  end

  it 'still accepts a year with accessible stats from the API' do
    expect do
      post api_v1_digests_path, params: { year: 2025 }, headers: headers
    end.to have_enqueued_job(Users::Digests::Yearly::CalculatingJob).with(user.id, 2025)
    expect(response).to have_http_status(:accepted)
  end

  %i[pro self_hosted].each do |access|
    it "keeps older years available with #{access} access" do
      if access == :pro
        user.update_column(:plan, User.plans[:pro])
      else
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      end
      get api_v1_digests_path, headers: headers
      expect(response.parsed_body['availableYears']).to include(2023)
      expect do
        post users_digests_path, params: { year: 2023 }
      end.to have_enqueued_job(Users::Digests::Yearly::CalculatingJob).with(user.id, 2023)
    end
  end
end
