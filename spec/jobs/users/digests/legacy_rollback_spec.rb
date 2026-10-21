# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rails digest rollback without Phoenix', type: :job do
  %w[month year].each do |period|
    it "recalculates #{period} stats and publishes legacy mail with no Phoenix schema" do
      user = create(:user, settings: { 'timezone' => 'Etc/UTC' })
      create(:point, user: user, timestamp: Time.utc(2024, 3, 1, 10).to_i)
      create(:stat, user: user, year: 2024, month: 3, distance: 999)
      klass = period == 'month' ? Users::Digests::Monthly::CalculatingJob : Users::Digests::Yearly::CalculatingJob
      mailer = period == 'month' ? Users::Digests::Monthly::EmailSendingJob : Users::Digests::Yearly::EmailSendingJob
      args = period == 'month' ? [user.id, 2024, 3] : [user.id, 2024]
      ActiveRecord::Base.connection.execute('DROP SCHEMA phoenix CASCADE')
      PhoenixSchema.reset!
      calculator_calls = 0
      allow_any_instance_of(Stats::CalculateMonth).to receive(:call).and_wrap_original do |original|
        calculator_calls += 1
        original.call
      end

      2.times { expect { klass.new(*args).perform_now }.to have_enqueued_job(mailer).with(*args) }

      expect(calculator_calls).to eq(period == 'month' ? 2 : 24)
      expect(user.digests.where(year: 2024).count).to eq(1)
      expect(user.digests.sole.period_type).to eq(period == 'month' ? 'monthly' : 'yearly')
      expect(user.stats.find_by!(year: 2024, month: 3).distance).to eq(0)
      expect(user.notifications.where(kind: :error)).to be_empty
      expect(PhoenixSchema.table?('digest_executions')).to be(false)
    end
  end
end
