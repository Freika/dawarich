# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Personal achievement history' do
  let(:user) { create(:user) }
  let(:place) { create(:place, user: user, latitude: 52.52, longitude: 13.405, name: 'Lake') }
  let(:selection) { Achievements::Selection.create!(user: user, place: place) }

  def visit(date, minutes: 30, status: :confirmed, confidence: nil, at: place)
    started_at = Time.iso8601(date)
    create(:visit, user: user, place: at, started_at: started_at,
                   ended_at: started_at + minutes.minutes, duration: minutes.minutes, status: status,
                   confidence: confidence)
  end

  def calculate(notify: false)
    selection
    Achievements::CollectionChecker.new(user, notify: notify).call
  end

  def card(series)
    user.achievement_collectibles.find_by!(series: series, subject_key: "place:#{place.id}")
  end

  it 'finds the place timezone locally and awards the five-year return from historical visits' do
    visit('2019-05-01T12:00:00Z')
    visit('2024-05-02T12:00:00Z')
    calculate

    expect(selection.reload.timezone).to eq('Europe/Berlin')
    expect(selection.timezone_source).to include('2026c')
    expect(card('return').level).to eq(3)
    expect(card('return').earned_at).to eq(Time.utc(2024, 5, 2, 12, 20))
    expect(card('return').events.where(kind: 'earned').pluck(:level)).to eq([1, 2, 3])
    expect(user.achievement_unlock_events).to be_empty
  end

  it 'compares with the previous qualifying visit rather than the first' do
    (2019..2024).each { |year| visit("#{year}-05-01T12:00:00Z") }
    calculate

    expect(card('return').level).to eq(0)
    expect(card('return').data['last_visit']).to include('2024-05-01')
  end

  it 'uses calendar anniversaries including February 29' do
    visit('2020-02-29T10:00:00Z', minutes: 20)
    visit('2021-02-28T10:20:00Z', minutes: 20)
    calculate

    expect(card('return').level).to eq(1)
  end

  it 'ignores short, declined, deleted and low-confidence suggested visits' do
    visit('2019-05-01T12:00:00Z')
    visit('2024-05-02T12:00:00Z', minutes: 19)
    visit('2024-05-03T12:00:00Z', status: :declined)
    visit('2024-05-04T12:00:00Z', status: :suggested, confidence: 69)
    visit('2024-05-05T12:00:00Z').update!(deleted_at: Time.current)
    calculate
    expect(card('return').level).to eq(0)

    visit('2024-05-06T12:00:00Z', status: :suggested, confidence: 70)
    calculate
    expect(card('return').level).to eq(3)
  end

  it 'collects seasons across years without using the profile timezone' do
    %w[2020-01-15T12:00:00Z 2021-04-15T12:00:00Z 2022-07-15T12:00:00Z 2023-10-15T12:00:00Z].each { |date| visit(date) }
    calculate
    expect(card('seasons').data.values_at('progress', 'season_mask')).to eq([4, 15])
    expect(card('seasons').level).to eq(1)
    user.update!(settings: user.settings.merge('timezone' => 'Pacific/Honolulu'))
    calculate
    expect(card('seasons').data['season_mask']).to eq(15)
  end

  it 'does not count one continuous stay in two seasons or use visits six days apart' do
    first = visit('2024-02-28T12:00:00Z')
    first.update!(ended_at: Time.utc(2024, 3, 2), duration: 3.days)
    visit('2024-03-05T12:00:00Z')
    calculate
    expect(card('seasons').data['progress']).to eq(1)

    visit('2024-03-06T12:00:00Z')
    calculate
    expect(card('seasons').data['progress']).to eq(2)
  end

  it 'searches alternative visit combinations at a season boundary' do
    %w[2020-02-28T12:00:00Z 2020-03-01T12:00:00Z 2020-04-01T12:00:00Z
       2020-07-01T12:00:00Z 2020-10-01T12:00:00Z].each { |date| visit(date) }
    calculate
    expect(card('seasons').level).to eq(1)
    expect(card('seasons').data['evidence'].map { |row| Time.iso8601(row['at']) }).to include(Time.utc(2020, 4, 1, 12))
  end

  it 'invalidates bulk changes and records revocation without awarding again on restoration' do
    visit('2019-05-01T12:00:00Z')
    recent = visit('2024-05-02T12:00:00Z')
    calculate
    expect(Achievements::CollectionState.find_by!(user: user)).to be_current
    Visit.where(id: recent.id).update_all(deleted_at: Time.current)
    expect(Achievements::CollectionState.find_by!(user: user)).not_to be_current
    calculate(notify: true)
    expect(card('return').level).to eq(0)
    expect(card('return').events.where(kind: 'revoked').count).to eq(1)

    recent.reload.update!(deleted_at: nil)
    calculate(notify: true)
    expect(card('return').level).to eq(3)
    expect(card('return').events.where(kind: 'earned').count).to eq(3)
    expect(user.achievement_unlock_events).to be_empty
  end

  it 'preserves personal card identity and first-earned history when places merge' do
    visit('2019-05-01T12:00:00Z')
    visit('2024-05-02T12:00:00Z')
    calculate
    old_card_id = card('return').id
    survivor = create(:place, user: user, latitude: 52.5201, longitude: 13.4051)

    Places::Merge.new(user: user, survivor: survivor, duplicate: place).call
    Achievements::CollectionChecker.new(user, notify: true).call

    merged = user.achievement_collectibles.find(old_card_id)
    expect(merged.subject_key).to eq("place:#{survivor.id}")
    expect(merged.level).to eq(3)
    expect(merged.events.where(kind: 'earned').count).to eq(3)
    expect(user.achievement_unlock_events).to be_empty
  end

  it 'silently refreshes changed timezone data and retains an explicit place override' do
    visit('2019-05-01T12:00:00Z')
    visit('2024-05-02T12:00:00Z')
    expect { calculate(notify: true) }.not_to(change { user.notifications.count })
    expect(user.achievement_unlock_events).to be_empty
    allow(Achievements::LocationTimezone).to receive(:version).and_return('timezone-fixture-v2')
    expect(Achievements::CollectionState.find_by!(user: user)).not_to be_current
    expect { calculate(notify: true) }.not_to(change { user.notifications.count })
    expect(selection.reload.timezone_source).to eq('timezone-fixture-v2')
    expect(Achievements::CollectionState.find_by!(user: user)).to be_current
    selection.update!(timezone: 'Pacific/Auckland', timezone_source: 'manual')
    calculate
    allow(Achievements::LocationTimezone).to receive(:version).and_return('timezone-fixture-v3')
    calculate
    expect(selection.reload.timezone).to eq('Pacific/Auckland')
    expect(selection.timezone_source).to eq('manual')
  end

  it 'keeps the previous consistent cards when source visits change during a calculation' do
    %w[2020-01-10T12:00:00Z 2020-04-10T12:00:00Z 2020-07-10T12:00:00Z
       2020-10-10T12:00:00Z].each { |date| visit(date) }
    calculate
    original = card('seasons').data.deep_dup
    place.update!(name: 'Changed name')
    allow(Achievements::SeasonsRule).to receive(:call).and_wrap_original do |method, *args, **options|
      result = method.call(*args, **options)
      user.visits.order(:id).last.update!(deleted_at: Time.current)
      result
    end
    calculate(notify: true)
    expect(card('seasons').data).to eq(original)
    expect(Achievements::CollectionState.find_by!(user: user)).not_to be_current
    allow(Achievements::SeasonsRule).to receive(:call).and_call_original
    calculate
    expect(card('seasons').level).to eq(0)
    expect(card('seasons').data['progress']).to eq(3)
  end

  it 'does not guess a timezone when the coordinate lookup is ambiguous' do
    allow(Achievements::LocationTimezone).to receive(:call).and_return(nil)
    calculate

    expect(card('seasons').data['status']).to eq('timezone_required')
    expect(card('seasons').level).to eq(0)
  end
end

RSpec.describe 'Personal collection notification batching' do
  it 'sends one digest for six new cards and never repeats it on replay' do
    user = create(:user)
    places = 6.times.map do |i|
      place = create(:place, user: user, name: "Fixture #{i}", latitude: 52.52, longitude: 13.405)
      user.achievement_selections.create!(place: place)
      place
    end
    Achievements::CollectionChecker.new(user, notify: false).call
    places.each do |place|
      [Time.utc(2019, 1, 1, 12), Time.utc(2025, 1, 2, 12)].each do |at|
        create(:visit, user: user, place: place, status: :confirmed,
                      started_at: at, ended_at: at + 30.minutes, duration: 1800)
      end
    end
    expect { Achievements::CollectionChecker.new(user).call }.to change { user.notifications.count }.by(1)
    expect(user.achievement_unlock_events.where(kind: 'collectible').count).to eq(6)
    expect { Achievements::CollectionChecker.new(user).call }.not_to(change { user.notifications.count })
  end
end
