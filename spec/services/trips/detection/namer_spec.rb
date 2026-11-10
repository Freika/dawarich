# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trips::Detection::Namer do
  subject(:namer) { described_class.new(user, started_at:, ended_at:) }

  let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }
  let(:started_at) { Time.utc(2026, 10, 12, 8) }
  let(:ended_at) { Time.utc(2026, 10, 18, 20) }

  around { |example| I18n.with_locale(:en) { example.run } }

  def point_at(time, city: nil, country: nil)
    create(:point, user:, timestamp: time.to_i, city:, country:)
  end

  it 'names a one-country trip after the city with the most days' do
    (12..14).each { |day| point_at(Time.utc(2026, 10, day, 12), city: 'Lisbon', country: 'Portugal') }
    5.times { |i| point_at(Time.utc(2026, 10, 15, 10 + i), city: 'Porto', country: 'Portugal') }

    expect(namer.call).to eq('Lisbon, Oct 2026')
  end

  it 'counts days in the user time zone' do
    user.update!(settings: { 'timezone' => 'America/New_York' })
    # Lisbon: two UTC days, one New York day. Porto: one UTC day, two New York days.
    point_at(Time.utc(2026, 10, 12, 12), city: 'Lisbon', country: 'Portugal')
    point_at(Time.utc(2026, 10, 13, 2), city: 'Lisbon', country: 'Portugal')
    point_at(Time.utc(2026, 10, 14, 1), city: 'Porto', country: 'Portugal')
    point_at(Time.utc(2026, 10, 14, 12), city: 'Porto', country: 'Portugal')

    expect(namer.call).to eq('Porto, Oct 2026')
  end

  it 'breaks a tie between cities by the one seen first' do
    point_at(Time.utc(2026, 10, 13, 12), city: 'Porto', country: 'Portugal')
    point_at(Time.utc(2026, 10, 14, 12), city: 'Lisbon', country: 'Portugal')

    expect(namer.call).to eq('Porto, Oct 2026')
  end

  it 'lists up to three countries in order of arrival' do
    %w[Portugal Spain France Italy].each_with_index do |country, i|
      point_at(Time.utc(2026, 10, 12 + i, 12), city: "City #{i}", country:)
    end

    expect(namer.call).to eq('Portugal, Spain, France, Oct 2026')
  end

  it 'names a one-country trip without cities after the country' do
    point_at(Time.utc(2026, 10, 13, 12), country: 'Portugal')

    expect(namer.call).to eq('Portugal, Oct 2026')
  end

  it 'ignores points outside the period' do
    point_at(Time.utc(2026, 10, 11, 12), city: 'Berlin', country: 'Germany')

    expect(namer.call).to eq('Trip, 12–18 Oct 2026')
  end

  it 'falls back to the date range when nothing is known' do
    expect(namer.call).to eq('Trip, 12–18 Oct 2026')
    expect(namer.call).to eq(namer.fallback)
  end

  it 'spells out both months and both years when the range crosses them' do
    expect(described_class.new(user, started_at: Time.utc(2026, 10, 28, 12),
                                     ended_at: Time.utc(2026, 11, 3, 12)).fallback)
      .to eq('Trip, 28 Oct – 3 Nov 2026')
    expect(described_class.new(user, started_at: Time.utc(2025, 12, 28, 12),
                                     ended_at: Time.utc(2026, 1, 3, 12)).fallback)
      .to eq('Trip, 28 Dec 2025 – 3 Jan 2026')
  end

  it 'takes the dates in the user time zone' do
    namer = described_class.new(user, started_at: Time.utc(2026, 10, 31, 23, 30), ended_at: Time.utc(2026, 11, 3, 12))
    point_at(Time.utc(2026, 11, 2, 12), country: 'Portugal')

    expect(namer.fallback).to eq('Trip, 1–3 Nov 2026')
    expect(namer.call).to eq('Portugal, Nov 2026')
  end

  it 'writes one full date when the trip starts and ends on the same local day' do
    namer = described_class.new(user, started_at: Time.utc(2026, 10, 12, 0), ended_at: Time.utc(2026, 10, 12, 20))

    I18n.with_locale(:zh) { expect(namer.fallback).to eq('旅行，2026年10月12日') }
  end

  it 'uses the current locale' do
    I18n.with_locale(:de) { expect(namer.fallback).to eq('Reise, 12.–18. Okt 2026') }
  end
end
