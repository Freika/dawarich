# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Failed import page on a self-hosted instance', type: :request do
  let(:user) { create(:user) }
  let(:import) do
    create(:import, user: user, status: :failed, error_message: 'PG::NumericValueOutOfRange: value out of range')
  end

  before { sign_in user }

  it 'shows the recorded error so the owner can diagnose it without an error tracker' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

    get import_path(import)

    failure = Nokogiri::HTML(response.body).at_css('[data-testid="import-failure"]')
    expect(failure.text).to include('PG::NumericValueOutOfRange: value out of range')
  end

  it 'keeps the recorded error off the page on Cloud' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

    get import_path(import)

    expect(response.body).not_to include('NumericValueOutOfRange')
  end
end
