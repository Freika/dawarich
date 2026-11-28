# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Date and time preferences in mailers', type: :mailer do
  include ActiveSupport::Testing::TimeHelpers

  let(:sent_at) { ActiveSupport::TimeZone['UTC'].local(2026, 10, 24, 14, 5) }
  let(:iso_admin) { create(:user, admin: true, settings: { 'date_format' => 'yyyy-mm-dd', 'timezone' => 'UTC' }) }

  let(:positional_mailer) do
    Class.new(ApplicationMailer) do
      def self.name
        'PositionalPreferencesMailer'
      end

      def stamped(user, time)
        with_user_locale(user) do
          mail(to: user.email, subject: 'Stamp', body: I18n.l(time, format: :human))
        end
      end
    end
  end

  it 'renders params-based mails with the recipient preferences' do
    travel_to(sent_at) do
      body = UsersMailer.with(user: iso_admin).test_email.body.encoded

      expect(body).to include('2026-10-24, 14:05')
    end
  end

  it 'renders positional mails with each recipient preferences, one after another' do
    dotted = create(:user, settings: { 'date_format' => 'dd.mm.yyyy', 'time_format' => '12h' })
    slashed = create(:user, settings: { 'date_format' => 'mm/dd/yyyy' })

    first = positional_mailer.stamped(dotted, sent_at).body.to_s
    second = positional_mailer.stamped(slashed, sent_at).body.to_s
    third = positional_mailer.stamped(create(:user), sent_at).body.to_s

    expect([first, second, third]).to eq(['24.10.2026, 2:05 PM', '10/24/2026, 14:05', '24 Oct 2026, 14:05'])
  end

  it 'leaves no preferences behind after rendering' do
    UsersMailer.with(user: iso_admin).test_email.body.encoded

    expect(I18n.l(sent_at, format: :human)).to eq('24 Oct 2026, 14:05')
  end
end
