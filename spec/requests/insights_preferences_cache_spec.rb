# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Insights fragment caches and date preferences', type: :request do
  let(:user) { create(:user) }
  let(:updated_at) { Time.zone.local(2026, 3, 5, 12, 0) }

  around do |example|
    caching = ActionController::Base.perform_caching
    ActionController::Base.perform_caching = true
    example.run
  ensure
    ActionController::Base.perform_caching = caching
  end

  before do
    create(:stat, user:, year: 2026, month: 1, distance: 100_000, updated_at:)
    sign_in user
  end

  it 'renders the new date preset on the next visit without waiting for the cache to expire' do
    get insights_url(year: 'all')
    expect(response.body).to include('5 March 2026')

    user.update!(settings: user.settings.merge('date_format' => 'dd.mm.yyyy'))
    get insights_url(year: 'all')

    expect(response.body).to include('05.03.2026')
  end
end
