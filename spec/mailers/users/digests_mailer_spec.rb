# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::DigestsMailer, type: :mailer do
  describe '#year_end_digest' do
    let(:user) { create(:user, email: 'test@example.com') }
    let(:digest) do
      create(:users_digest,
             user: user,
             year: 2025,
             period_type: :yearly,
             distance: 4287,
             toponyms: [{ 'country' => 'Germany', 'cities' => [] }],
             monthly_distances: (1..12).map { |m| [m.to_s, 300 + m * 10] }.to_h,
             time_spent_by_location: {
               'countries' => [{ 'name' => 'Germany', 'minutes' => 456_000 }],
               'cities' => []
             },
             first_time_visits: { 'countries' => [], 'cities' => [] },
             year_over_year: { 'distance_change_percent' => 18 },
             all_time_stats: { 'total_countries' => 12, 'total_cities' => 84, 'total_distance' => '12345' })
    end
    let(:mail) { Users::DigestsMailer.with(user: user, digest: digest).year_end_digest }

    it 'sends to the user with the expected subject' do
      expect(mail.to).to eq [user.email]
      expect(mail.subject).to include '2025 Year in Review'
    end

    it 'includes ASCII monthly distance bars in both parts' do
      html_part = mail.html_part.body.to_s
      text_part = mail.text_part.body.to_s
      expect(html_part).to include('█')
      expect(text_part).to include('█')
      expect(html_part).to include('MONTHLY DISTANCE')
      expect(text_part).to include('MONTHLY DISTANCE')
    end

    it 'includes the email-digests unsubscribe anchor' do
      expect(mail.html_part.body.to_s).to include('email-digests')
      expect(mail.text_part.body.to_s).to include('email-digests')
    end

    context 'when the user prefers kilometers' do
      let(:user) { create(:user, email: 'test@example.com') }
      let(:digest) do
        create(:users_digest,
               user: user, year: 2025, period_type: :yearly,
               distance: 500_000,
               monthly_distances: { '1' => 50_000, '2' => 100_000 },
               time_spent_by_location: { 'countries' => [], 'cities' => [] },
               first_time_visits: { 'countries' => [], 'cities' => [] },
               year_over_year: {},
               all_time_stats: { 'total_countries' => 1, 'total_cities' => 1, 'total_distance' => '500000' })
      end

      it 'converts the total distance from meters to km in both parts' do
        expect(mail.html_part.body.to_s).to match(/Distance\s+500\s+km/)
        expect(mail.text_part.body.to_s).to match(/Distance\s+500\s+km/)
      end

      it 'converts the monthly bar values from meters to km' do
        expect(mail.html_part.body.to_s).to match(/50\s+km/)
        expect(mail.html_part.body.to_s).to match(/100\s+km/)
        expect(mail.html_part.body.to_s).not_to match(/50000\s+km/)
      end
    end

    context 'when the user prefers miles' do
      let(:user) do
        create(:user, email: 'test@example.com',
                      settings: { 'maps' => { 'distance_unit' => 'mi' } })
      end
      let(:digest) do
        create(:users_digest,
               user: user, year: 2025, period_type: :yearly,
               distance: 1_609_340,
               monthly_distances: { '1' => 1_609_340 },
               time_spent_by_location: { 'countries' => [], 'cities' => [] },
               first_time_visits: { 'countries' => [], 'cities' => [] },
               year_over_year: {},
               all_time_stats: { 'total_countries' => 1, 'total_cities' => 1, 'total_distance' => '1609340' })
      end

      it 'converts the total distance from meters to mi' do
        expect(mail.html_part.body.to_s).to match(/Distance\s+1,000\s+mi/)
        expect(mail.text_part.body.to_s).to match(/Distance\s+1,000\s+mi/)
      end
    end
  end

  describe '#monthly_digest' do
    let(:user) { create(:user, email: 'test@example.com') }
    let(:digest) do
      create(:users_digest,
             user: user,
             year: 2026, month: 3, period_type: :monthly,
             distance: 312,
             monthly_distances: { '1' => 10, '2' => 20, '3' => 312 },
             time_spent_by_location: { 'countries' => [], 'cities' => [] },
             first_time_visits: { 'countries' => [], 'cities' => [] },
             year_over_year: {})
    end
    let(:mail) { Users::DigestsMailer.with(user: user, digest: digest).monthly_digest }

    it 'sends to the user with the expected subject' do
      expect(mail.to).to eq [user.email]
      expect(mail.subject).to include('March 2026')
      expect(mail.subject).to include('in review')
    end

    it 'renders ASCII content in both HTML and text parts' do
      expect(mail.html_part.body.to_s).to include('OVERVIEW')
      expect(mail.text_part.body.to_s).to include('OVERVIEW')
      expect(mail.html_part.body.to_s).to include('email-digests')
    end

    context 'when monthly_distances is stored as Array of [day, distance] pairs (pre-normalization data)' do
      let(:digest) do
        create(:users_digest,
               user: user, year: 2026, month: 3, period_type: :monthly,
               distance: 312,
               monthly_distances: [[1, 10], [2, 20], [3, 40], [4, 80], [5, 312]],
               time_spent_by_location: { 'countries' => [], 'cities' => [] },
               first_time_visits: { 'countries' => [], 'cities' => [] },
               year_over_year: {})
      end

      it 'renders a real sparkline (not a single flat block)' do
        # Bug regression: when monthly_distances is an Array of integer-indexed pairs and the
        # template uses string-key lookup, every lookup returns nil and the sparkline collapses.
        # After normalization the template must produce 5 non-zero chars in the sparkline.
        # Use the plain-text part so we don't have to strip HTML (and avoid CodeQL's
        # "incomplete HTML sanitization" warning for a test-only regex).
        text = mail.text_part.body.to_s
        sparkline_section = text[/DAILY DISTANCE\n([^\n]+)/, 1]
        expect(sparkline_section).not_to be_nil
        chars = sparkline_section.scan(/[▁▂▃▄▅▆▇█]/)
        expect(chars.size).to eq 5
      end
    end

    context 'when year_over_year["distance_change_percent"] is -100 (full drop from prior period)' do
      let(:digest) do
        create(:users_digest,
               user: user, year: 2026, month: 3, period_type: :monthly,
               distance: 0,
               monthly_distances: { '1' => 0 },
               time_spent_by_location: { 'countries' => [], 'cities' => [] },
               first_time_visits: { 'countries' => [], 'cities' => [] },
               year_over_year: { 'distance_change_percent' => -100 })
      end

      it 'does not raise FloatDomainError when rendering' do
        # Bug regression: `@digest.distance / (1 + pct/100)` with pct=-100 yields Infinity
        # then NaN.round → FloatDomainError. ascii_trend_from_pct must guard this.
        expect { mail.html_part.body.to_s }.not_to raise_error
        expect { mail.text_part.body.to_s }.not_to raise_error
      end
    end

    context 'when the user prefers kilometers' do
      let(:user) { create(:user, email: 'test@example.com') }
      let(:digest) do
        create(:users_digest,
               user: user, year: 2026, month: 3, period_type: :monthly,
               distance: 312_000,
               monthly_distances: { '1' => 10_000, '2' => 20_000, '3' => 312_000 },
               time_spent_by_location: { 'countries' => [], 'cities' => [] },
               first_time_visits: { 'countries' => [], 'cities' => [] },
               year_over_year: {})
      end

      it 'converts the total distance from meters to km' do
        expect(mail.html_part.body.to_s).to match(/Distance\s+312\s+km/)
        expect(mail.text_part.body.to_s).to match(/Distance\s+312\s+km/)
      end

      it 'converts weekday bar values from meters to km' do
        expect(mail.html_part.body.to_s).not_to match(/\b312000 km\b/)
      end
    end

    context 'when the user prefers miles' do
      let(:user) do
        create(:user, email: 'test@example.com',
                      settings: { 'maps' => { 'distance_unit' => 'mi' } })
      end
      let(:digest) do
        create(:users_digest,
               user: user, year: 2026, month: 3, period_type: :monthly,
               distance: 1_609_340,
               monthly_distances: { '1' => 1_609_340 },
               time_spent_by_location: { 'countries' => [], 'cities' => [] },
               first_time_visits: { 'countries' => [], 'cities' => [] },
               year_over_year: {})
      end

      it 'converts the total distance from meters to mi' do
        expect(mail.html_part.body.to_s).to match(/Distance\s+1,000\s+mi/)
        expect(mail.text_part.body.to_s).to match(/Distance\s+1,000\s+mi/)
      end
    end
  end
end
