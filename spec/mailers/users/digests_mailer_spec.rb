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
        all_time_stats: { 'total_countries' => 12, 'total_cities' => 84, 'total_distance' => '12345' }
      )
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
        year_over_year: {}
      )
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
  end
end
