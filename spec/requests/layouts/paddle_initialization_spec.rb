# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Paddle initialization', type: :request do
  it 'keeps Cloud Paddle initialization inside the onload attribute' do
    environment = 'sandbox"<'
    token = 'token"<'

    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('PADDLE_BILLING_ENVIRONMENT', 'production').and_return(environment)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('PADDLE_BILLING_CLIENT_TOKEN').and_return(token)

    get '/users/sign_in'

    script = Nokogiri::HTML5(response.body).at_css("script[src='https://cdn.paddle.com/paddle/v2/paddle.js']")
    expected = <<~ONLOAD.chomp
      Paddle.Environment.set(#{environment.to_json});
      Paddle.Initialize({ token: #{token.to_json} });
    ONLOAD
    expected = "\n        #{expected.gsub("\n", "\n        ").rstrip}\n      "

    expect(script['onload']).to eq(expected)
  end

  it 'does not render Paddle for self-hosted instances' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

    get '/users/sign_in'

    script = Nokogiri::HTML5(response.body).at_css("script[src='https://cdn.paddle.com/paddle/v2/paddle.js']")

    expect(script).to be_nil
  end
end
