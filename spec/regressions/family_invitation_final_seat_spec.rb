# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe 'Family invitation final seat' do
  self.use_transactional_tests = false

  let!(:owner) { create(:user) }
  let!(:family) { create(:family, creator: owner) }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    @user_ids = [owner.id]
    create(:family_membership, user: owner, family: family, role: :owner)
    3.times do
      member = create(:user)
      @user_ids << member.id
      create(:family_membership, user: member, family: family, role: :member)
    end
    clear_enqueued_jobs
  end

  after do
    family.family_invitations.delete_all
    family.family_memberships.delete_all
    family.delete
    User.unscoped.where(id: @user_ids).find_each do |user|
      user.notifications.delete_all
      user.delete
    end
  end

  it 'refreshes cached capacity before reserving a seat' do
    expect(family.full?).to be false
    create(:family_invitation, family: Family.find(family.id), invited_by: owner, email: 'reserved@example.com')
    service = Families::Invite.new(family: family, email: 'later@example.com', invited_by: owner)

    expect(service.call).to be false
    expect(family.family_invitations.active.count).to eq(1)
    expect(Family::Invitations::SendingJob).not_to have_been_enqueued
  end

  it 'admits only one concurrent invitation for the final Cloud seat' do
    entered = Queue.new
    release = Queue.new
    second_pid = Queue.new
    results = Queue.new
    errors = Queue.new
    allow(Family::Invitations::SendingJob).to receive(:perform_later).and_wrap_original do |original, id|
      if Family::Invitation.find(id).email == 'first@example.com'
        entered << true
        release.pop
      end
      original.call(id)
    end

    first = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        results << Families::Invite.new(family: Family.find(family.id), email: 'first@example.com',
                                        invited_by: User.find(owner.id)).call
      end
    rescue StandardError => e
      errors << e
    end
    Timeout.timeout(10) { entered.pop }
    second = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        second_pid << connection.select_value('SELECT pg_backend_pid()')
        results << Families::Invite.new(family: Family.find(family.id), email: 'second@example.com',
                                        invited_by: User.find(owner.id)).call
      end
    rescue StandardError => e
      errors << e
    end
    pid = Timeout.timeout(10) { second_pid.pop }
    Timeout.timeout(10) do
      loop do
        break if !results.empty? || !errors.empty?
        break if ActiveRecord::Base.connection.select_value(
          "SELECT wait_event_type = 'Lock' FROM pg_stat_activity WHERE pid = #{Integer(pid)}"
        )

        Thread.pass
      end
    end
    release << true
    [first, second].each { |thread| expect(thread.join(10)).to be_present }

    expect(errors.size).to eq(0)
    expect([results.pop, results.pop]).to contain_exactly(true, false)
    expect(family.family_invitations.active.count).to eq(1)
  ensure
    release << true if release
    [first, second].compact.each { |thread| thread.kill if thread.alive? }
  end
end
