# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Flipper admin UI throttling', type: :request do
  let(:admin) { create(:user, :admin) }

  before do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
    sign_in admin
  end

  after do
    Rack::Attack.enabled = false
  end

  def browse_flipper(times)
    (1..times).map do
      get '/admin/flipper/features'
      response.status
    end
  end

  context 'when self-hosted' do
    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    end

    it 'does not rate-limit the flipper UI' do
      expect(browse_flipper(31)).not_to include(429)
    end
  end

  context 'when not self-hosted' do
    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    end

    it 'rate-limits the flipper UI after 30 requests' do
      expect(browse_flipper(31).last).to eq(429)
    end
  end
end
