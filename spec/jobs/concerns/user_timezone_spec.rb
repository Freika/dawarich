# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserTimezone, type: :concern do
  # Create a dummy class that includes the concern
  let(:dummy_class) do
    Class.new do
      include UserTimezone

      def test_method(user)
        with_user_timezone(user) do
          Time.zone.name
        end
      end
    end
  end

  let(:dummy_instance) { dummy_class.new }
  let(:user) { create(:user, settings: { 'timezone' => 'America/New_York' }) }

  describe '#with_user_timezone' do
    it 'sets Time.zone to user timezone during block execution' do
      original_zone = Time.zone.name

      result = dummy_instance.test_method(user)

      expect(result).to eq('America/New_York')
      expect(Time.zone.name).to eq(original_zone) # Restored after block
    end

    it 'restores original timezone even if block raises error' do
      original_zone = Time.zone.name

      dummy_class_with_error = Class.new do
        include UserTimezone

        def test_method_with_error(user)
          with_user_timezone(user) do
            raise StandardError, 'test error'
          end
        end
      end

      instance = dummy_class_with_error.new

      expect { instance.test_method_with_error(user) }.to raise_error(StandardError, 'test error')
      expect(Time.zone.name).to eq(original_zone)
    end

    it 'works with UTC timezone' do
      utc_user = create(:user, settings: { 'timezone' => 'UTC' })

      result = dummy_instance.test_method(utc_user)

      expect(result).to eq('UTC')
    end

    it 'falls back to UTC when user has invalid timezone' do
      invalid_tz_user = create(:user, settings: { 'timezone' => 'Invalid/Zone' })

      result = dummy_instance.test_method(invalid_tz_user)

      expect(result).to eq('UTC')
    end
  end
end
