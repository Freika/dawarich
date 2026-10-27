# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Places::ListQuery' do
  let(:user) { create(:user) }

  it 'searches names case insensitively and treats wildcard characters literally' do
    literal = create(:place, user:, name: 'Cafe 100%_Berlin')
    create(:place, user:, name: 'Cafe 100xxBerlin')
    create(:place, name: literal.name)

    expect(Places::ListQuery.new(user:, params: { q: '100%_bER' }).call).to contain_exactly(literal)
  end

  it 'filters tags with any-of semantics without duplicating places' do
    first, second = create_list(:tag, 2, user:)
    both = create(:place, user:, tags: [first, second])
    one = create(:place, user:, tags: [first])
    create(:place, user:)

    expect(Places::ListQuery.new(user:, params: { tag_ids: [first.id, second.id] }).call).to contain_exactly(both, one)
  end

  it 'sorts by active visit count and last visit while excluding declined and deleted visits' do
    older = create(:place, user:, name: 'Alpha')
    recent = create(:place, user:, name: 'Zulu')
    empty = create(:place, user:, name: 'Empty')
    create(:visit, user:, place: older, started_at: 5.days.ago)
    create(:visit, user:, place: recent, started_at: 2.days.ago)
    create(:visit, user:, place: recent, started_at: 1.day.ago)
    create(:visit, user:, place: older, status: :declined)
    create(:visit, user:, place: older, deleted_at: Time.current)

    %w[visit_count last_visit].each do |sort|
      records = Places::ListQuery.new(user:, params: { sort: }).call.to_a
      expect(records).to eq([recent, older, empty])
      expect(records.map { |place| place.active_visit_count.to_i }).to eq([2, 1, 0])
    end
  end

  it 'defaults to name order for unknown sort input and preserves unconfirmed semantics' do
    create(:place, user:, name: 'Manual')
    zulu = create(:place, user:, name: 'Zulu', source: :photon)
    alpha = create(:place, user:, name: 'Alpha', source: :photon)

    expect(Places::ListQuery.new(user:, params: { filter: 'unconfirmed', sort: 'name; DROP TABLE places' }).call)
      .to eq([alpha, zulu])
  end
end
