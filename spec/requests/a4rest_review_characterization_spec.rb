# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'A4 rest concurrent writes', type: :request, non_transactional: true do
  let(:user) { create(:user) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

  before do
    %w[visits places].each { ActiveRecord::Base.connection.reset_pk_sequence!(_1) }
  end

  after do
    Note.where(user_id: user.id).delete_all
    Visit.unscoped.where(user_id: user.id).delete_all
    Area.where(user_id: user.id).delete_all
  end

  it 'preserves a body PATCH committed after the title PATCH loads its note' do
    note = create(:note, user: user, title: 'Before', body: 'Before')
    subscription = after_select('FROM "notes"', 'concurrent body', note.id)
    patch "/api/v1/notes/#{note.id}", params: { note: { title: 'Edited title' } }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(note.reload.attributes.values_at('title', 'body')).to eq(['Edited title', 'concurrent body'])
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription) if subscription
  end

  it 'preserves a decline committed after a name PATCH loads its confirmed visit' do
    visit = create(:visit, area: nil, user: user, status: :confirmed, name: 'Before')
    subscription = after_select('FROM "visits"', :declined, visit.id)
    patch "/api/v1/visits/#{visit.id}", params: { visit: { name: 'Edited name' } }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(visit.reload.attributes.values_at('name', 'status')).to eq(['Edited name', 'declined'])
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription) if subscription
  end

  it 'bulk confirm retains active predicates at the write and counts only surviving IDs' do
    first = create(:visit, area: nil, user: user, status: :confirmed)
    second = create(:visit, area: nil, user: user, status: :suggested)
    scope = user.scoped_visits
    relation = scope.where(id: [first.id, second.id, -1])
    allow(user).to receive(:scoped_visits).and_return(scope)
    allow(scope).to receive(:where).with(id: [first.id, second.id, -1]).and_return(relation)
    allow(relation).to receive(:update_all).and_wrap_original do |original, **attrs|
      concurrent_sql("UPDATE visits SET status=2 WHERE id=#{first.id}")
      original.call(**attrs)
    end
    clear_enqueued_jobs
    result = Visits::BulkUpdate.new(user, [first.id, second.id, -1], 'confirmed').call
    expect(result.fetch(:count)).to eq(1)
    expect(first.reload).to be_declined
    expect(second.reload).to be_confirmed
    expect(enqueued_jobs).to eq([])
  end

  it 'bulk decline retains tombstone predicates and captured orphan effects for partial IDs' do
    place = create(:place, user: user)
    first = create(:visit, area: nil, user: user, status: :confirmed, place: place)
    second = create(:visit, area: nil, user: user, status: :suggested, place: place)
    scope = user.scoped_visits
    relation = scope.where(id: [first.id, second.id, -1])
    allow(user).to receive(:scoped_visits).and_return(scope)
    allow(scope).to receive(:where).with(id: [first.id, second.id, -1]).and_return(relation)
    allow(relation).to receive(:update_all).and_wrap_original do |original, **attrs|
      concurrent_sql("UPDATE visits SET deleted_at=NOW() WHERE id=#{first.id}")
      original.call(**attrs)
    end
    clear_enqueued_jobs
    result = Visits::BulkUpdate.new(user, [first.id, second.id, -1], 'declined').call
    expect(result.fetch(:count)).to eq(1)
    expect(Visit.unscoped.find(first.id)).to be_confirmed
    expect(second.reload).to be_declined
    expect(enqueued_jobs.map { [_1[:job], _1[:args]] }).to eq([[Places::DeleteIfOrphanJob, [place.id]]])
  end

  def after_select(fragment, value, id)
    fired = false
    parent = Thread.current
    ActiveSupport::Notifications.subscribe('sql.active_record') do |event|
      sql = event.payload[:sql]
      next unless Thread.current == parent && !fired && sql.start_with?('SELECT') && sql.include?(fragment)

      fired = true
      if fragment.include?('notes')
        concurrent_sql("UPDATE notes SET body=#{ActiveRecord::Base.connection.quote(value)} WHERE id=#{id}")
      else
        concurrent_sql("UPDATE visits SET status=2 WHERE id=#{id}")
      end
    end
  end

  def concurrent_sql(sql)
    primary = ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()')
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        expect(connection.select_value('SELECT pg_backend_pid()')).not_to eq(primary)
        connection.execute(sql)
      end
    end.value
  end
end
