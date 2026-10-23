# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Point writes during an atomic import', :non_transactional do
  let!(:user) { create(:user) }
  let(:month_start) { Time.utc(2026, 10, 1).to_i }

  after do
    Points::Revision.where(user_id: user.id).delete_all
    Tracks::Revision.where(user_id: user.id).delete_all
  end

  it 'do not wait for the import transaction to commit' do
    inserted = Queue.new
    release = Queue.new

    importer = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Revisions::ImportTransaction.call(user.id) do
          Point.upsert_all(
            [{ user_id: user.id, timestamp: month_start + 3600, lonlat: 'POINT(13.4 52.5)' }],
            unique_by: %i[user_id timestamp lonlat], on_duplicate: :skip
          )
          inserted << true
          release.pop
        end
      end
    end
    expect(inserted.pop(timeout: 10)).to be(true)

    live_write = lambda do
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout = '1s'")
        create(:point, user:, timestamp: month_start + 7200)
      end
    end

    expect(&live_write).not_to raise_error
  ensure
    release << true
    importer&.join
  end
end
