# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

RSpec.describe 'Administrator removal guards', type: :request do
  self.use_transactional_tests = false

  let!(:actor) { create(:user, :admin, password: 'synthetic-password-123') }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    sign_in actor
    clear_enqueued_jobs
  end

  after do
    User.unscoped.where(id: @owner_ids || [actor.id]).find_each do |owner|
      owner.notifications.delete_all
      owner.delete
    end
  end

  it 'refuses direct deletion of the acting administrator' do
    other = create(:user, :admin, password: 'synthetic-password-123')
    @owner_ids = [actor.id, other.id]

    delete settings_user_path(actor)

    expect(actor.reload.deleted_at).to be_nil
    expect(Users::DestroyJob).not_to have_been_enqueued
    expect(flash[:alert]).to be_present
  end

  [false, 'false', '0'].each do |value|
    it "refuses sole administrator demotion with #{value.inspect}" do
      patch settings_user_path(actor), params: { user: { admin: value } }, as: :json

      expect(actor.reload.admin?).to be true
      expect(flash[:alert]).to be_present
    end
  end

  it 'does not count an inactive administrator as remaining access' do
    other = create(:user, :admin, status: :inactive)
    @owner_ids = [actor.id, other.id]
    other.update!(status: :inactive)

    patch settings_user_path(actor), params: { user: { status: 'inactive' } }

    expect(actor.reload.status).to eq('active')
  end

  it 'retains administration access when deletion races with demotion' do
    other = create(:user, :admin, password: 'synthetic-password-123')
    @owner_ids = [actor.id, other.id]
    entered = Queue.new
    release = Queue.new
    original = User.instance_method(:mark_as_deleted_atomically!)
    allow_any_instance_of(User).to receive(:mark_as_deleted_atomically!) do |target|
      if target.id == other.id
        entered << true
        release.pop
      end
      original.bind_call(target)
    end
    failures = Queue.new
    first = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        client = ActionDispatch::Integration::Session.new(Rails.application)
        client.post user_session_path, params: { user: { email: actor.email, password: 'synthetic-password-123' } }
        client.delete settings_user_path(other)
      end
    rescue StandardError => e
      failures << e
    end
    Timeout.timeout(10) { entered.pop }
    second = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        client = ActionDispatch::Integration::Session.new(Rails.application)
        client.post user_session_path, params: { user: { email: other.email, password: 'synthetic-password-123' } }
        client.patch settings_user_path(actor), params: { user: { admin: '0' } }
      end
    rescue StandardError => e
      failures << e
    end
    sleep 0.3
    release << true
    Timeout.timeout(10) { [first, second].each(&:join) }
    raise failures.pop unless failures.empty?

    expect(User.where(id: @owner_ids, admin: true, status: :active).count).to eq(1)
  ensure
    release << true if release
    [first, second].compact.each { |thread| thread.kill if thread.alive? }
  end
end
