# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::SlimCollectionQuery do
  let(:user) { create(:user) }

  it 'returns a payload byte-identical to Api::SlimPointSerializer' do
    create_list(:point, 3, user: user)
    relation = user.points.order(:timestamp)

    expected = relation.map { |point| Api::SlimPointSerializer.new(point).call }

    expect(described_class.new(relation).call).to eq(expected)
  end

  it 'resolves country_name through the country association' do
    country = create(:country, name: 'Germany')
    point = create(:point, user: user)
    point.update_columns(country_id: country.id)

    result = described_class.new(user.points.where(id: point.id)).call

    expect(result.first[:country_name]).to eq('Germany')
  end

  it 'falls back to an empty string when no country information exists' do
    point = create(:point, user: user)
    point.update_columns(country_id: nil)

    result = described_class.new(user.points.where(id: point.id)).call

    expect(result.first[:country_name]).to eq('')
  end

  it 'reads the device combo through the dimension' do
    source = PointSource.create!(digest: 'a' * 32, tracker_id: 'dimension-device')
    point = create(:point, user: user, source: source)

    result = described_class.new(user.points.where(id: point.id)).call

    expect(result.first[:tracker_id]).to eq('dimension-device')
    expect(result.first).to eq(Api::SlimPointSerializer.new(point.reload).call)
  end

  it 'reads a nil tracker on an unstamped row, like the model does' do
    point = create(:point, user: user)

    result = described_class.new(user.points.where(id: point.id)).call

    expect(result.first[:tracker_id]).to be_nil
    expect(result.first).to eq(Api::SlimPointSerializer.new(point.reload).call)
  end

  it 'preserves the relation order' do
    p1 = create(:point, user: user, timestamp: 100)
    p2 = create(:point, user: user, timestamp: 200)

    result = described_class.new(user.points.order(timestamp: :desc)).call

    expect(result.map { |row| row[:id] }).to eq([p2.id, p1.id])
  end
end
