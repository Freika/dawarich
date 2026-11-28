# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Insights analytics event', type: :request do
  let(:user) { create(:user) }

  def insights_viewed_states
    Nokogiri::HTML(response.body)
            .css('[data-controller="analytics-event"][data-analytics-event-name-value="insights_viewed"]')
            .map { |signal| JSON.parse(signal['data-analytics-event-props-value'])['state'] }
  end

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    sign_in user
  end

  it 'reports an empty screen' do
    get insights_path

    expect(insights_viewed_states).to eq(['empty'])
  end

  it 'reports a screen with statistics for the selected period' do
    create(:stat, user:, year: Time.current.year, month: 1, distance: 80_000)

    get insights_path

    expect(insights_viewed_states).to eq(['with_data'])
  end

  it 'reports insufficient data when the user has points but no statistics for the period' do
    create(:point, user:)

    get insights_path

    expect(insights_viewed_states).to eq(['insufficient_data'])
  end

  it 'does not report a year switch as another opening' do
    create(:stat, user:, year: Time.current.year, month: 1, distance: 80_000)

    get insights_path(year: Time.current.year)

    expect(insights_viewed_states).to be_empty
  end

  it 'reports nothing on self-hosted instances' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

    get insights_path

    expect(insights_viewed_states).to be_empty
  end
end
