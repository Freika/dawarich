# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'points:raw_data:reset_all' do
  before do
    Rake::Task['points:raw_data:reset_all'].reenable
  end

  context 'when there is nothing to reset' do
    it 'prints nothing to reset and exits' do
      expect { Rake::Task['points:raw_data:reset_all'].invoke }.to output(/Nothing to reset/).to_stdout
    end
  end

  context 'when user declines confirmation' do
    let(:user) { create(:user) }
    let!(:archive) { create(:points_raw_data_archive, user: user) }
    let!(:point) do
      create(:point, user: user, raw_data_archived: true, raw_data_archive_id: archive.id)
    end

    before do
      allow($stdin).to receive(:gets).and_return("n\n")
    end

    it 'aborts without deleting anything' do
      expect do
        Rake::Task['points:raw_data:reset_all'].invoke
      end.to output(/Aborted/).to_stdout

      expect(point.reload.raw_data_archived).to be true
      expect(Points::RawDataArchive.count).to eq(1)
    end
  end

  context 'when user confirms' do
    let(:user) { create(:user) }
    let!(:archive) { create(:points_raw_data_archive, user: user) }
    let!(:point) do
      create(:point, user: user, raw_data_archived: true,
             raw_data_archive_id: archive.id, raw_data: { 'some' => 'data' })
    end

    before do
      allow($stdin).to receive(:gets).and_return("y\n")
    end

    it 'resets archival flags on points' do
      expect do
        Rake::Task['points:raw_data:reset_all'].invoke
      end.to output(/Reset 1 points/).to_stdout

      point.reload
      expect(point.raw_data_archived).to be false
      expect(point.raw_data_archive_id).to be_nil
    end

    it 'deletes archive records' do
      expect do
        Rake::Task['points:raw_data:reset_all'].invoke
      end.to output(/Deleted 1 archive records/).to_stdout
                                                .and change(Points::RawDataArchive, :count).from(1).to(0)
    end
  end

  context 'when CONFIRM=true bypasses prompt' do
    let(:user) { create(:user) }
    let!(:archive) { create(:points_raw_data_archive, user: user) }
    let!(:point) do
      create(:point, user: user, raw_data_archived: true,
             raw_data_archive_id: archive.id, raw_data: { 'some' => 'data' })
    end

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('CONFIRM').and_return('true')
    end

    it 'resets without prompting' do
      expect($stdin).not_to receive(:gets)

      expect do
        Rake::Task['points:raw_data:reset_all'].invoke
      end.to output(/Reset Complete/).to_stdout
    end
  end
end
