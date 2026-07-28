# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PlanScopable do
  let(:user) { create(:user) }

  describe '#plan_restricted?' do
    context 'when self-hosted' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

      it 'returns false for lite users' do
        user.update!(plan: :lite)
        expect(user.plan_restricted?).to be false
      end

      it 'returns false for pro users' do
        user.update!(plan: :pro)
        expect(user.plan_restricted?).to be false
      end
    end

    context 'when cloud-hosted' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      it 'returns true for lite users' do
        user.update!(plan: :lite)
        expect(user.plan_restricted?).to be true
      end

      it 'returns false for pro users' do
        user.update!(plan: :pro)
        expect(user.plan_restricted?).to be false
      end

      it 'returns false for family owners' do
        owner = create(:user, plan: :family, skip_auto_trial: true)
        family = create(:family, creator: owner)
        create(:family_membership, :owner, family: family, user: owner)

        expect(owner.plan_restricted?).to be false
      end

      it 'returns false for a lite member of a family-plan family' do
        owner = create(:user, plan: :family, skip_auto_trial: true)
        family = create(:family, creator: owner)
        create(:family_membership, :owner, family: family, user: owner)
        member = create(:user, plan: :lite, skip_auto_trial: true)
        create(:family_membership, family: family, user: member)

        expect(member.plan_restricted?).to be false
      end
    end
  end

  describe 'scoped relations for a lite family member' do
    let(:owner) { create(:user, plan: :family, skip_auto_trial: true) }
    let(:family) { create(:family, creator: owner) }
    let(:member) { create(:user, plan: :lite, skip_auto_trial: true) }

    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      create(:family_membership, :owner, family: family, user: owner)
      create(:family_membership, family: family, user: member)
    end

    it 'returns unscoped points, tracks, visits and stats' do
      recent_point = create(:point, user: member, timestamp: 1.month.ago.to_i)
      old_point = create(:point, user: member, timestamp: 2.years.ago.to_i)
      recent_track = create(:track, user: member, start_at: 1.month.ago)
      old_track = create(:track, user: member, start_at: 2.years.ago)

      expect(member.scoped_points).to include(recent_point, old_point)
      expect(member.scoped_tracks).to include(recent_track, old_track)
    end
  end

  describe '#data_window_start' do
    it 'returns approximately 12 months ago' do
      expect(user.data_window_start).to be_within(1.second).of(12.months.ago)
    end
  end

  describe '#scoped_points' do
    let!(:recent_point) do
      create(:point, user: user, timestamp: 1.month.ago.to_i)
    end
    let!(:old_point) do
      create(:point, user: user, timestamp: 2.years.ago.to_i)
    end

    context 'when user is not plan-restricted' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

      it 'returns all points' do
        result = user.scoped_points
        expect(result).to include(recent_point, old_point)
      end
    end

    context 'when user is plan-restricted (lite on cloud)' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        user.update!(plan: :lite)
      end

      it 'returns only points within the data window' do
        result = user.scoped_points
        expect(result).to include(recent_point)
        expect(result).not_to include(old_point)
      end
    end

    context 'when point is exactly at boundary' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        user.update!(plan: :lite)
      end

      let!(:boundary_point) do
        create(:point, user: user, timestamp: 12.months.ago.to_i)
      end

      it 'includes points at the exact boundary' do
        result = user.scoped_points
        expect(result).to include(boundary_point)
      end
    end
  end

  describe '#scoped_tracks' do
    let!(:recent_track) do
      create(:track, user: user, start_at: 1.month.ago)
    end
    let!(:old_track) do
      create(:track, user: user, start_at: 2.years.ago)
    end

    context 'when user is not plan-restricted' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

      it 'returns all tracks' do
        result = user.scoped_tracks
        expect(result).to include(recent_track, old_track)
      end
    end

    context 'when user is plan-restricted (lite on cloud)' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        user.update!(plan: :lite)
      end

      it 'returns only tracks within the data window' do
        result = user.scoped_tracks
        expect(result).to include(recent_track)
        expect(result).not_to include(old_track)
      end
    end
  end

  describe '#scoped_visits' do
    let(:area) { create(:area, user: user) }
    let!(:recent_visit) do
      create(:visit, user: user, area: area, started_at: 1.month.ago, ended_at: 1.month.ago + 1.hour)
    end
    let!(:old_visit) do
      create(:visit, user: user, area: area, started_at: 2.years.ago, ended_at: 2.years.ago + 1.hour)
    end

    context 'when user is not plan-restricted' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

      it 'returns all visits' do
        result = user.scoped_visits
        expect(result).to include(recent_visit, old_visit)
      end
    end

    context 'when user is plan-restricted (lite on cloud)' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        user.update!(plan: :lite)
      end

      it 'returns only visits within the data window' do
        result = user.scoped_visits
        expect(result).to include(recent_visit)
        expect(result).not_to include(old_visit)
      end
    end
  end

  describe '#scoped_stats' do
    let!(:recent_stat) do
      create(:stat, user: user, year: Time.current.year, month: Time.current.month)
    end
    let!(:old_stat) do
      create(:stat, user: user, year: Time.current.year - 2, month: 1)
    end

    context 'when user is not plan-restricted' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

      it 'returns all stats' do
        result = user.scoped_stats
        expect(result).to include(recent_stat, old_stat)
      end
    end

    context 'when user is plan-restricted (lite on cloud)' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        user.update!(plan: :lite)
      end

      it 'returns only stats within the data window' do
        result = user.scoped_stats
        expect(result).to include(recent_stat)
        expect(result).not_to include(old_stat)
      end
    end

    context 'when stat is at the boundary month' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        user.update!(plan: :lite)
      end

      let(:cutoff) { 12.months.ago }
      let!(:boundary_stat) do
        create(:stat, user: user, year: cutoff.year, month: cutoff.month)
      end

      it 'includes stats at the exact boundary month' do
        result = user.scoped_stats
        expect(result).to include(boundary_stat)
      end
    end
  end
end
