# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::BatchUpdate do
  let(:user) { create(:user) }
  let!(:first) { create(:point, user: user, altitude: 1) }
  let!(:second) { create(:point, user: user, altitude: 2) }
  let!(:untouched) { create(:point, user: user, altitude: 3) }

  it 'updates only the listed rows, applying the cast' do
    updated = described_class.column(:altitude, { first.id => 36.7, second.id => nil }, cast: 'real')

    expect(updated).to eq(2)
    expect(first.reload.altitude).to be_within(0.001).of(36.7)
    expect(second.reload.altitude).to be_nil
    expect(untouched.reload.altitude).to eq(3)
  end

  it 'writes jsonb values' do
    described_class.column(:motion_data, { first.id => { 'm' => 1 }.to_json }, cast: 'jsonb')

    expect(first.reload.motion_data).to eq({ 'm' => 1 })
  end

  it 'is a no-op for an empty batch' do
    expect(described_class.column(:altitude, {}, cast: 'real')).to eq(0)
  end
end
