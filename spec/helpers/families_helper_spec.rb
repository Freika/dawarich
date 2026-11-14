# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FamiliesHelper, type: :helper do
  describe '#mobile_invitation_url' do
    it 'carries the URL-encoded origin of the request and the token' do
      invitation = build(:family_invitation, token: 'abc_DEF-123')
      allow(helper.request).to receive(:base_url).and_return('https://dawarich.example.test:8443')

      url = helper.mobile_invitation_url(invitation)

      expect(url).to eq('dawarich://invite?server=https%3A%2F%2Fdawarich.example.test%3A8443&token=abc_DEF-123')
    end
  end
end
