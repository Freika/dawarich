# frozen_string_literal: true

require 'rails_helper'

# Checkout tokens must never be rendered into page URLs: analytics scripts
# record outbound clicks with the full href. Links go through
# /trial/upgrade, which mints the token at redirect time.
RSpec.describe 'Checkout links', type: :request do
  let(:user) { create(:user, :trial, settings: { 'onboarding_completed' => true }) }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    stub_const('MANAGER_URL', 'https://manager.example.test')
    sign_in user
  end

  %w[/imports /users/edit].each do |path|
    it "renders no checkout token on #{path}" do
      get path

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('auth/dawarich?token=')
      expect(response.body).not_to match(/[?&]token=ey/)
    end
  end

  it 'tags the navbar subscribe buttons as a checkout start for Rybbit, with a token-free destination' do
    get '/imports'

    html = Nokogiri::HTML(response.body)
    buttons = html.css('a[data-rybbit-event="checkout_started"]')

    expect(buttons).not_to be_empty
    buttons.each do |button|
      expect(button['href']).to eq('/trial/upgrade')
      expect(button['data-turbo']).to eq('false')
      expect(button['data-rybbit-prop-destination']).to eq('https://manager.example.test/auth/dawarich')
    end
  end

  it 'does not tag the resume link of a pending-payment user as a checkout start' do
    user.update!(status: :pending_payment)

    get '/imports'

    expect(response.body).not_to include('data-rybbit-event="checkout_started"')
  end
end
