# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'points:raw_data:archive' do
  before do
    allow(PointsChannel).to receive(:broadcast_to)
    Rake::Task['points:raw_data:archive'].reenable
  end

  context 'with eligible points across users' do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }

    before do
      old_date = 3.months.ago.beginning_of_month
      create_list(:point, 3, user: user, timestamp: old_date.to_i, raw_data: { lon: 13.4, lat: 52.5 })
      create_list(:point, 2, user: other_user, timestamp: old_date.to_i, raw_data: { lon: 14.0, lat: 53.0 })
    end

    it 'archives points for all users' do
      expect do
        expect { Rake::Task['points:raw_data:archive'].invoke }.to output(/Points archived: 5/).to_stdout
      end.to change(Points::RawDataArchive, :count).by(2)

      expect(Point.where(raw_data_archived: true).count).to eq(5)
    end
  end

  context 'with no eligible points' do
    it 'completes without archiving' do
      expect do
        expect { Rake::Task['points:raw_data:archive'].invoke }.to output(/Points archived: 0/).to_stdout
      end.not_to change(Points::RawDataArchive, :count)
    end
  end

  context 'when the per-user advisory lock is held' do
    let(:user) { create(:user) }

    before do
      old_date = 3.months.ago.beginning_of_month
      create_list(:point, 2, user: user, timestamp: old_date.to_i, raw_data: { lon: 13.4, lat: 52.5 })
      allow(ActiveRecord::Base).to receive(:with_advisory_lock).and_return(false)
    end

    it 'skips the locked user without archiving and says so' do
      expect do
        expect { Rake::Task['points:raw_data:archive'].invoke }
          .to output(/Skipping user #{user.id}.*Points archived: 0/m).to_stdout
      end.not_to change(Points::RawDataArchive, :count)
    end
  end
end

RSpec.describe 'points:raw_data:archive_full' do
  before do
    allow(PointsChannel).to receive(:broadcast_to)
    Rake::Task['points:raw_data:archive_full'].reenable
  end

  let(:user) { create(:user) }

  it 'does not clear archives verified within the cooling period' do
    old_date = 3.months.ago.beginning_of_month
    points = create_list(:point, 3, user: user, timestamp: old_date.to_i, raw_data: { lon: 13.4, lat: 52.5 })

    expect { Rake::Task['points:raw_data:archive_full'].invoke }.to output(/Cleared 0 points/).to_stdout

    expect(points.each(&:reload).map(&:raw_data)).to all(eq({ 'lon' => 13.4, 'lat' => 52.5 }))
  end

  it 'clears archives verified before the cooling period' do
    old_date = 3.months.ago.beginning_of_month
    create_list(:point, 3, user: user, timestamp: old_date.to_i, raw_data: { lon: 13.4, lat: 52.5 })
    Points::RawData::Archiver.new.archive_user(user.id)
    Points::RawDataArchive.where(user_id: user.id).update_all(verified_at: 8.days.ago)

    expect { Rake::Task['points:raw_data:archive_full'].invoke }.to output(/Cleared 3 points/).to_stdout

    expect(Point.where(user: user, raw_data: {}).count).to eq(3)
  end
end
