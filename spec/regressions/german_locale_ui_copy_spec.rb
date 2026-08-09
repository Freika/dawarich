# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'German interface copy', type: :helper do
  helper DatetimeFormattingHelper

  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    I18n.with_locale(:de) { example.run }
  end

  it 'distinguishes registration from sign-in actions' do
    expect(I18n.t('home.index.sign_up')).to eq('Registrieren')
    expect(I18n.t('home.index.sign_in')).to eq('Anmelden')
  end

  it 'describes map controls by their user-visible effect' do
    expect(I18n.t('shared.days_per_country.distinct_days_with_at_least_one_tracked_point_per_country'))
      .to eq('Unterschiedliche Kalendertage mit mindestens einem aufgezeichneten Punkt pro Land. Keine Steuerberatung.')
    expect(I18n.t('map.maplibre.settings_panel.untagged')).to eq('🏷️ Ohne Tag')
    expect(I18n.t('map.maplibre.settings_panel.clear_radius_around_visited_points'))
      .to eq('Radius des aufgedeckten Bereichs um besuchte Punkte')
    expect(I18n.t('map.maplibre.button_cluster.replay')).to eq('Wiedergabe')
    expect(I18n.t('javascript.messages.cannot_update_recalculation_is_already_in_progress'))
      .to eq('Aktualisierung nicht möglich: Eine Neuberechnung läuft bereits.')
    expect(I18n.t('settings.integrations.index.upgrade_to_pro')).to eq('Auf Pro upgraden')
  end

  it 'places relative-time words in natural German order' do
    travel_to Time.zone.local(2026, 8, 5, 12) do
      three_days = helper.relative_distance_in_words(3.days.ago)
      one_day = helper.relative_distance_in_words(1.day.from_now)

      expect(I18n.t('common.time_ago', time: three_days)).to eq('vor 3 Tagen')
      expect(I18n.t('common.time_from_now', time: one_day)).to eq('in einem Tag')
      expect(I18n.t('families.show.invited_ago_expires', ago: three_days, date: '8. Aug.'))
        .to eq('Vor 3 Tagen eingeladen · läuft am 8. Aug. ab')
    end
  end

  it 'uses complete sentences for copy whose word order varies by locale' do
    expect(I18n.t('devise.registrations.points_usage.summary_html', used: '42', limit: '100'))
      .to eq('Du hast 42 von 100 verfügbaren Punkten verwendet.')
    expect(I18n.t('family_mailer.invitation.invited_by_family_text',
                  email: 'anna@example.com', family: 'Reisefreunde'))
      .to eq('anna@example.com hat dich eingeladen, der Familie „Reisefreunde“ auf Dawarich beizutreten.')
    expect(I18n.t('family_mailer.member_joined.member_count', count: 2))
      .to eq('Deine Familie hat jetzt 2 Mitglieder.')
  end

  it 'uses correct plural and feature terminology' do
    expect(I18n.t('javascript.search.locations_found', count: 2)).to eq('2 Standorte gefunden')
    expect(I18n.t('users.digests.public_year.first_time_count', count: 2)).to eq('2 erstmals besucht')
    expect(I18n.t('services.families.accept_invitation.you_must_leave_your_current_family_before_joining_a_new'))
      .to eq('Du musst deine aktuelle Familie verlassen, bevor du einer neuen beitreten kannst.')
  end

  it 'renders clear German security emails in HTML and text' do
    user = create(:user, settings: { 'locale' => 'de' })

    oauth_html, oauth_text = I18n.with_locale(:de) do
      mail = UsersMailer.with(
        user: user,
        provider_label: 'Google',
        link_url: 'https://example.test/link'
      ).oauth_account_link
      [mail.html_part.body.decoded, mail.text_part.body.decoded]
    end
    otp_html, otp_text = I18n.with_locale(:de) do
      mail = UsersMailer.with(user: user).otp_account_locked
      [mail.html_part.body.decoded, mail.text_part.body.decoded]
    end

    expect(oauth_html).to include('Warst du das nicht?')
    expect(oauth_text).to include('Anmeldemethode Google mit deinem Dawarich-Konto zu verknüpfen')
    expect(otp_html).to include('Möglicherweise versucht jemand, auf dein Konto zuzugreifen')
    expect(otp_text).to include('Wenn du das warst, musst du nichts unternehmen')
  end

  it 'keeps the request locale for signup mail before the preference is persisted' do
    user = create(:user)

    subject = I18n.with_locale(:de) { UsersMailer.with(user: user).welcome.subject }

    expect(subject).to eq('Willkommen bei Dawarich!')
  end

  it 'renders grammatical German family emails in HTML and text' do
    owner = create(:user, email: 'anna@example.com', settings: { 'locale' => 'de' })
    family = create(:family, creator: owner, name: 'Reise & Freunde')
    create(:family_membership, :owner, family: family, user: owner)
    member = create(:user, email: 'ben@example.com')
    create(:family_membership, family: family, user: member)
    invitation = create(:family_invitation, family: family, invited_by: owner)

    invitation_html, invitation_text = I18n.with_locale(:de) do
      mail = FamilyMailer.invitation(invitation)
      [mail.html_part.body.decoded, mail.text_part.body.decoded]
    end
    joined_html, joined_text = I18n.with_locale(:de) do
      mail = FamilyMailer.member_joined(family, member)
      [mail.html_part.body.decoded, mail.text_part.body.decoded]
    end

    expect(invitation_html).to include('der Familie „<strong>Reise &amp; Freunde</strong>“')
    expect(invitation_text).to include('der Familie „Reise & Freunde“ auf Dawarich beizutreten')
    expect(joined_html).to include('Deine Familie hat jetzt <strong>2</strong> Mitglieder.')
    expect(joined_text).to include('Deine Familie hat jetzt 2 Mitglieder.')
    expect(joined_text).not_to include("ben@example.com's")
  end

  it 'uses the persisted locale when a digest is rendered outside a request' do
    user = create(:user, settings: { 'locale' => 'de' })
    digest = create(
      :users_digest,
      user: user,
      year: 2026,
      month: 8,
      period_type: :monthly,
      distance: 1_000,
      monthly_distances: { '1' => 1_000 },
      time_spent_by_location: { 'countries' => [], 'cities' => [] },
      first_time_visits: { 'countries' => [], 'cities' => [] },
      year_over_year: {}
    )

    subject, html = I18n.with_locale(:en) do
      mail = Users::DigestsMailer.with(user: user, digest: digest).monthly_digest
      [mail.subject, mail.html_part.body.decoded]
    end

    expect(subject).to eq('Dein August 2026 im Rückblick — Dawarich')
    expect(html).to include('ÜBERBLICK')
  end
end
