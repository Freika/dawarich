# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Revisions::ImportTransaction do
  let(:user) { create(:user) }
  let(:october) { Time.utc(2026, 10, 15).to_i }
  let(:december) { Time.utc(2026, 12, 15).to_i }

  def point_revisions
    Points::Revision.where(user_id: user.id).order(:month).pluck(:month, :revision).to_h
  end

  def track_revisions
    Tracks::Revision.where(user_id: user.id).order(:month).pluck(:month, :revision).to_h
  end

  it 'does not touch revisions inside the block' do
    described_class.call(user.id) do
      create(:point, user:, timestamp: october)

      expect(point_revisions).to be_empty
    end
  end

  it 'bumps every month that holds points of the user after the block' do
    create(:point, user:, timestamp: october)
    before = point_revisions

    described_class.call(user.id) { create(:point, user:, timestamp: december) }

    expect(point_revisions.keys).to eq([Date.new(2026, 10, 1), Date.new(2026, 12, 1)])
    expect(point_revisions[Date.new(2026, 10, 1)]).not_to eq(before[Date.new(2026, 10, 1)])
  end

  it 'adds one revision for an outlying point instead of every month up to it' do
    described_class.call(user.id) do
      create(:point, user:, timestamp: october)
      create(:point, user:, timestamp: Time.utc(1970, 1, 2).to_i)
    end

    expect(point_revisions.keys).to eq([Date.new(1970, 1, 1), Date.new(2026, 10, 1)])
  end

  it 'limits the bump to the months of the given import' do
    create(:point, user:, timestamp: october)
    before = point_revisions
    import = create(:import, user:)

    described_class.call(user.id, import_id: import.id) do
      create(:point, user:, import:, timestamp: december)
    end

    expect(point_revisions[Date.new(2026, 10, 1)]).to eq(before[Date.new(2026, 10, 1)])
    expect(point_revisions.keys).to include(Date.new(2026, 12, 1))
  end

  it 'bumps the months covered by the user tracks after the block' do
    described_class.call(user.id) do
      create(:track, user:, start_at: Time.zone.at(october), end_at: Time.zone.at(october) + 1.hour)

      expect(track_revisions).to be_empty
    end

    expect(track_revisions.keys).to eq([Date.new(2026, 10, 1)])
  end

  it 'leaves track revisions alone for an import' do
    create(:track, user:, start_at: Time.zone.at(october), end_at: Time.zone.at(october) + 1.hour)
    before = track_revisions
    import = create(:import, user:)

    described_class.call(user.id, import_id: import.id) { create(:point, user:, import:, timestamp: october) }

    expect(track_revisions).to eq(before)
  end

  it 'records revisions again for writes after the block' do
    described_class.call(user.id) { nil }

    create(:point, user:, timestamp: october)

    expect(point_revisions.keys).to eq([Date.new(2026, 10, 1)])
  end

  it 'keeps revisions deferred for the rest of an enclosing import' do
    described_class.call(user.id) do
      described_class.call(user.id) { nil }
      create(:point, user:, timestamp: december)

      expect(point_revisions).to be_empty
    end
  end

  it 'returns the block value' do
    expect(described_class.call(user.id) { :imported }).to eq(:imported)
  end

  it 'records revisions again after the block raises' do
    expect do
      described_class.call(user.id) { raise ArgumentError, 'broken file' }
    end.to raise_error(ArgumentError)

    create(:point, user:, timestamp: october)

    expect(point_revisions.keys).to eq([Date.new(2026, 10, 1)])
  end
end
