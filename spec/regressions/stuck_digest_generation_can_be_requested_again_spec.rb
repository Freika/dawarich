# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A digest whose generation job was lost', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  before do
    sign_in user
    create(:stat, user: user, year: 2025, month: 1)
    ActiveJob::Base.queue_adapter = :test
  end

  it 'can be requested again once the pending state is stale' do
    post users_digests_path, params: { year: 2025 }
    clear_enqueued_jobs

    travel(Users::Digest::GENERATION_STALE_AFTER + 1.minute) do
      expect { post users_digests_path, params: { year: 2025 } }
        .to have_enqueued_job(Users::Digests::Yearly::CalculatingJob).exactly(:once)
    end
  end

  it 'offers a retry on the web and the year again in the API once stale' do
    post users_digests_path, params: { year: 2025 }

    travel(Users::Digest::GENERATION_STALE_AFTER + 1.minute) do
      get users_digests_path
      page = Nokogiri::HTML(response.body)
      expect(page.at_css('[data-digest-pending="2025"]')).to be_nil
      expect(response.body).to include(I18n.t('ux_p2.digest.failed'))
      expect(page.css('form').any? { |form| form['action'].to_s.include?('year=2025') }).to be(true)

      get api_v1_digests_url, headers: { 'Authorization' => "Bearer #{user.api_key}" }
      expect(response.parsed_body['availableYears']).to include(2025)
    end
  end

  it 'still refuses a second request while generation is recent' do
    post users_digests_path, params: { year: 2025 }
    clear_enqueued_jobs

    expect { post users_digests_path, params: { year: 2025 } }
      .not_to have_enqueued_job(Users::Digests::Yearly::CalculatingJob)
  end
end
