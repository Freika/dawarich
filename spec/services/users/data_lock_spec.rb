# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::DataLock, :non_transactional, threads: 3 do
  let(:user) { create(:user) }

  it 'allows concurrent readers and makes deletion wait for them' do
    reader_started = Queue.new
    release_reader = Queue.new
    second_reader_entered = Queue.new
    deletion_entered = Queue.new

    first_reader = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        described_class.with_shared(user.id) do
          reader_started << true
          release_reader.pop
        end
      end
    end

    Timeout.timeout(5) { reader_started.pop }

    second_reader = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        described_class.with_shared(user.id) { second_reader_entered << true }
      end
    end

    expect(Timeout.timeout(5) { second_reader_entered.pop }).to be true

    deletion = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        described_class.with_exclusive(user.id) { deletion_entered << true }
      end
    end

    expect { Timeout.timeout(0.2) { deletion_entered.pop } }.to raise_error(Timeout::Error)

    release_reader << true

    expect(Timeout.timeout(5) { deletion_entered.pop }).to be true
    [first_reader, second_reader, deletion].each { |thread| thread.join(5) }
  ensure
    release_reader << true if first_reader&.alive?
    [first_reader, second_reader, deletion].compact.each { |thread| thread.join(5) }
  end
end
