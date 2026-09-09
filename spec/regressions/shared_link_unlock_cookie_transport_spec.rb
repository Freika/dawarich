# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Shared-link unlock cookie transport security', type: :request do
  let(:link) { create(:shared_link, :with_phrase) }

  before do
    allow(Rails.env).to receive(:production?).and_return(true)
  end

  it 'allows the unlock cookie over HTTP' do
    post unlock_public_shared_link_path(link), params: { phrase: 'blau-tiger-berg' }

    cookie = response.headers['Set-Cookie']
    expect(cookie).to be_present
    expect(cookie).not_to include('secure')
  end

  it 'protects the unlock cookie over HTTPS' do
    https!
    post unlock_public_shared_link_path(link), params: { phrase: 'blau-tiger-berg' }

    expect(response.headers['Set-Cookie']).to include('secure')
  end
end
