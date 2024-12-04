# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Photoprism::CachePreviewToken, type: :service do
  let(:user) { double('User', id: 1) }
  let(:preview_token) { 'sample_token' }
  let(:service) { described_class.new(user, preview_token) }

  describe '#call' do
    it 'writes the preview token to the cache with the correct key' do
      expect(Rails.cache).to receive(:write).with(
        "dawarich/photoprism_preview_token_#{user.id}", preview_token
      )

      service.call
    end
  end
end
