# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleMaps::PhoneTakeoutParser do
  describe '#call' do
    subject(:parser) { described_class.new(import, user.id).call }

    let(:user) { create(:user) }
    let(:file_path) { Rails.root.join('spec/fixtures/files/google/phone-takeout.json') }
    let(:raw_data) { JSON.parse(File.read(file_path)) }
    let(:import) { create(:import, user:, name: 'phone_takeout.json', raw_data:) }

    context 'when file exists' do
      it 'creates points' do
        expect { parser }.to change { Point.count }.by(4)
      end
    end
  end
end
