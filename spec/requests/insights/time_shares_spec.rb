# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Insights: where the time went', type: :request do
  let(:user) { create(:user) }
  let(:year) { 1.year.ago.year }

  before do
    sign_in user
    create(:stat, user:, year:, month: 3, distance: 12_000)
    home = create(:place, user:)
    create(:home, user:, place: home)
    create(:visit, user:, place: home, started_at: Time.zone.local(year, 3, 2, 0),
                   ended_at: Time.zone.local(year, 3, 2, 20))
  end

  it 'shows where the days and hours of the year went' do
    get details_insights_path(year:)

    card = Capybara.string(response.body).find('[data-testid="time-shares"]')
    expect(card).to have_text(I18n.t('insights.time_shares.days_title'))
    expect(card).to have_text(I18n.t('insights.time_shares.hours_title'))
    expect(card).to have_css('svg circle[stroke-dasharray]', minimum: 2)
  end

  it 'leaves the card out of the all-time view' do
    get details_insights_path(year: 'all')

    expect(response.body).not_to include('data-testid="time-shares"')
  end
end
