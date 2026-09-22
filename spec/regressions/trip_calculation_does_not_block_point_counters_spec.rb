# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Trip calculation while points arrive', :non_transactional do
  {
    Trips::CalculatePathJob => [:calculate_path, ->(trip_id) { [trip_id] }],
    Trips::CalculateDistanceJob => [:calculate_distance, ->(trip_id) { [trip_id, 'km'] }],
    Trips::CalculateCountriesJob => [:calculate_countries, ->(trip_id) { [trip_id, 'km'] }]
  }.each do |job_class, (calculation, arguments)|
    it "lets the owner's points counter update while #{job_class.name} runs" do
      user = create(:user)
      trip = create(:trip, user:)
      calculating = Queue.new
      finish = Queue.new
      allow(Trips::CalculateAllJob).to receive(:tally_completion)
      allow_any_instance_of(Trip).to receive(calculation) do
        calculating << true
        finish.pop
      end

      job = Thread.new { job_class.perform_now(*arguments.call(trip.id)) }
      calculating.pop

      counter_update = begin
        User.transaction do
          User.connection.execute("SET LOCAL lock_timeout = '500ms'")
          User.update_counters(user.id, points_count: 1)
        end
        :applied
      rescue ActiveRecord::LockWaitTimeout
        :blocked
      ensure
        finish << true
        job.join
      end

      expect(counter_update).to eq(:applied)
    ensure
      Trip.where(user_id: user.id).delete_all if user
      user&.reload&.destroy!
    end
  end

  it 'still makes hard deletion of the owner wait while a path is calculated' do
    user = create(:user)
    trip = create(:trip, user:)
    calculating = Queue.new
    finish = Queue.new
    allow(Trips::CalculateAllJob).to receive(:tally_completion)
    allow_any_instance_of(Trip).to receive(:calculate_path) do
      calculating << true
      finish.pop
    end

    job = Thread.new { Trips::CalculatePathJob.perform_now(trip.id) }
    calculating.pop

    deletion = begin
      User.transaction do
        User.connection.execute("SET LOCAL lock_timeout = '500ms'")
        User.connection.execute("DELETE FROM users WHERE id = #{user.id}")
      end
      :deleted
    rescue ActiveRecord::LockWaitTimeout
      :waited
    rescue ActiveRecord::InvalidForeignKey
      :reached_constraints
    ensure
      finish << true
      job.join
    end

    expect(deletion).to eq(:waited)
  ensure
    Trip.where(user_id: user.id).delete_all if user
    user&.reload&.destroy!
  end
end
