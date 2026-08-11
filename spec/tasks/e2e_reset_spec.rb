# frozen_string_literal: true

require 'rails_helper'

describe 'e2e:reset' do
  let!(:demo_user) { create(:user, email: 'demo@dawarich.app') }
  let!(:worker_user) { create(:user, email: 'e2e-worker2@dawarich.app') }
  let!(:worker_family_member) { create(:user, email: 'family.member1.w2@dawarich.app') }
  let!(:regular_user) { create(:user, email: 'someone@example.com') }

  before do
    [demo_user, worker_user, worker_family_member, regular_user].each do |user|
      create(:point, user: user)
    end
  end

  it 'wipes worker clones from prior seeds even when E2E_PARALLEL_USERS is unset' do
    Rake::Task['e2e:reset'].execute

    expect(demo_user.points.count).to eq(0)
    expect(worker_user.points.count).to eq(0)
    expect(worker_family_member.points.count).to eq(0)
    expect(regular_user.points.count).to eq(1)
  end
end
