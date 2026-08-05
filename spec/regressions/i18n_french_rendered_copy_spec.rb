# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rendered French copy' do
  def normalized_parts(mail)
    [mail.html_part, mail.text_part].compact.map do |part|
      body = part.body.to_s
      part.mime_type == 'text/html' ? Nokogiri::HTML(body).text.squish : body.squish
    end
  end

  it 'renders localized relative time and statistics month labels' do
    user = create(:user)
    create(:stat, user:, year: 2026, month: 8, distance: 1_000)

    I18n.with_locale(:fr) do
      relative_time = [I18n.t('datetime.distance_in_words.about_x_hours', count: 2),
                       I18n.t('families.show.ago')].join(' ')

      expect(relative_time).to eq('environ 2 heures auparavant')
      expect(Stat.year_distance(2026, user)[7].first).to eq('août')
    end
  end

  it 'renders family emails as complete French sentences' do
    family = create(:family, name: "Famille d'Élodie")
    invitation = create(:family_invitation, family:, invited_by: family.creator)
    member = create(:user, email: 'membre@example.com')

    I18n.with_locale(:fr) do
      invitation_parts = normalized_parts(FamilyMailer.invitation(invitation))
      member_parts = normalized_parts(FamilyMailer.member_joined(family, member))

      invitation_parts.each do |body|
        expected_invitation = "#{family.creator.email} vous a invité à rejoindre " \
                              "sa famille « Famille d'Élodie » sur Dawarich."
        expect(body).to include(expected_invitation)
      end
      member_parts.each do |body|
        expect(body).to include('membre@example.com : sa localisation actuelle (si le partage est activé)')
        expect(body).not_to include("'s")
      end
    end
  end

  it 'renders account-linking and deletion warnings with their full meaning' do
    user = create(:user, email: 'utilisateur@example.com')

    I18n.with_locale(:fr) do
      oauth_parts = normalized_parts(
        UsersMailer.with(user:, provider_label: 'Google', link_url: 'https://example.test/link').oauth_account_link
      )
      deletion_parts = normalized_parts(
        UsersMailer.with(user:, link_url: 'https://example.test/delete').account_destroy_confirmation
      )

      oauth_parts.each do |body|
        expect(body).to include('mode de connexion Google à votre compte Dawarich')
        expect(body).not_to include("d'inscrire un compte")
      end
      deletion_parts.each do |body|
        irreversible_warning = 'Après confirmation, tout votre historique de localisation, vos trajets, zones, ' \
                               'visites, voyages et appartenances à des familles seront définitivement supprimés.'
        expect(body).to include(irreversible_warning)
        expect(body).to include('résilier')
        expect(body).not_to include("#{user.email}, , Nous avons")
        expect(body).not_to include('supprimés."')
      end
    end
  end

  it 'renders French weekday and month labels in digest emails' do
    user = create(:user, settings: { 'locale' => 'fr' })
    yearly_digest = create(:users_digest, user:, year: 2026)
    monthly_digest = create(:users_digest, :monthly, user:, year: 2026, month: 8)

    yearly_mail = Users::DigestsMailer.with(user:, digest: yearly_digest).year_end_digest
    monthly_mail = Users::DigestsMailer.with(user:, digest: monthly_digest).monthly_digest

    I18n.with_locale(:fr) do
      yearly_parts = normalized_parts(yearly_mail)
      monthly_parts = normalized_parts(monthly_mail)

      expect(yearly_mail.subject).to eq('Bilan annuel 2026 — Dawarich')
      expect(monthly_mail.subject).to eq('Bilan mensuel — août 2026 — Dawarich')
      yearly_parts.each do |body|
        expect(body).to include("Bilan de l'année 2026")
        expect(body).to include("Voici votre année 2026 en un coup d'œil.")
        expect(body).to include('jan.')
        expect(body).not_to match(/\bJan\b/)
      end
      monthly_parts.each do |body|
        expect(body).to include('Bilan mensuel — août 2026')
        expect(body).to include('votre historique de localisation le mois dernier')
        expect(body).to include('lun')
        expect(body).not_to match(/\bMon\b/)
      end
    end
  end

  it 'renders the trial deadline and feature promise naturally in both email parts' do
    user = create(:user)

    I18n.with_locale(:fr) do
      normalized_parts(UsersMailer.with(user:).explore_features).each do |body|
        expect(body).to include('Revivez vos voyages')
        expect(body).to include('Il vous reste 5 jours')
        expect(body).to include('pour profiter au maximum de votre essai')
      end
    end
  end

  it 'provides plural-aware French labels for every MapLibre loading source' do
    I18n.with_locale(:fr) do
      expected_labels = {
        anomalies: ['1 anomalie', '2 anomalies'],
        areas: ['1 zone', '2 zones'],
        family: ['1 membre de la famille', '2 membres de la famille'],
        flights: ['1 vol', '2 vols'],
        hexagons: ['1 hexagone', '2 hexagones'],
        photos: ['1 photo', '2 photos'],
        places: ['1 lieu', '2 lieux'],
        points: ['1 point', '2 points'],
        tracks: ['1 trajet', '2 trajets'],
        visits: ['1 visite', '2 visites']
      }

      expected_labels.each do |source, (singular, plural)|
        key = "javascript.loading_sources.#{source}"
        expect(I18n.t(key, count: 0, formatted_count: 0)).to eq(plural.sub('2', '0'))
        expect(I18n.t(key, count: 1, formatted_count: 1)).to eq(singular)
        expect(I18n.t(key, count: 2, formatted_count: 2)).to eq(plural)
      end

      expect(I18n.t('map.maplibre.settings_panel.tracks')).to eq('Trajets')
      expect(I18n.t('javascript.messages.failed_to_load_tracks')).to eq('Échec du chargement des trajets')
      expect(I18n.t('javascript.map_info.track_number', id: 12)).to eq('Trajet 12')
      expect(I18n.t('javascript.map_info.tracks')).to eq('Trajets')
      expect(I18n.t('javascript.map_info.show_points_help')).to include('modifier le trajet')
    end
  end

  it 'keeps recognizable import formats and GeoJSON terminology' do
    I18n.with_locale(:fr) do
      expect(I18n.t('imports.form.records_json_semantic_history_phone_takeout_json')).to include('Phone Takeout')
      expect(I18n.t('imports.form.takeout_metadata_sidecars_json')).to include('Google Takeout')
      expect(I18n.t('imports.form.feature_collections_json_geojson')).to include("Collections d'entités")
      expect(I18n.t('imports.extraction_card.tracks')).to eq('trajets,')
      expect(I18n.t('imports.extraction_dialog.tracks')).to eq('Trajets')
      expect(I18n.t('enums.shared_link.resource_type.track')).to eq('Trajet')
      expect(I18n.t('users_mailer.explore_features.visualize_your_tracks_on_beautiful_maps_with_different_layers_and'))
        .to include('vos trajets')
    end
  end

  it 'uses idiomatic self-hosting and shared-link recovery copy' do
    I18n.with_locale(:fr) do
      expect(I18n.t('home.index.self_hosted_and_private')).to eq('Auto-hébergé et privé')
      expect(I18n.t('home.index.maintain_complete_control_over_your_data_with_our_self_hosted'))
        .to include('solution auto-hébergée', 'en toute sérénité')
      expect(I18n.t('shared.links.not_found.the_owner_may_have_revoked_the_link_or_it_may'))
        .to include('Le propriétaire')
      expect(I18n.t('shared.links.phrase_prompt.this_shared_link_is_protected_ask_the_owner_for_the'))
        .to include('propriétaire du lien')
      expect(I18n.t('shared.links.phrase_prompt.unlock')).to eq('Déverrouiller')
    end
  end

  it 'localizes labels that were previously locked to English' do
    I18n.with_locale(:fr) do
      expect(I18n.t('imports.index.file_size')).to eq('Taille du fichier')
      expect(I18n.t('points.index.all_imports')).to eq('Toutes les importations')
      expect(I18n.t('insights.index.total_distance')).to eq('Distance totale')
      expect(I18n.t('insights.index.countries')).to eq('Pays')
      expect(I18n.t('insights.index.cities')).to eq('Villes')
      expect(I18n.t('insights.index.days_traveling')).to eq('Jours de déplacement')
      expect(I18n.t('controllers.insights.all_time')).to eq('Depuis toujours')
      expect(I18n.t('controllers.insights.year_overview', year: 2026)).to eq('Résumé de 2026')
      expect(I18n.t('map.maplibre.settings_panel.enrich_photos')).to eq('Enrichir les photos')
      expect(I18n.t('map.timeline_feeds.day.no_visits_tracked_this_day'))
        .to eq('Aucune visite enregistrée ce jour-là.')
      expect(I18n.t('map.timeline_feeds.day_summary.total_distance_traveled_this_day'))
        .to eq('Distance totale parcourue ce jour-là')
      expect(I18n.t('insights.activity_heatmap.mon')).to eq('Lun')
      expect(I18n.t('insights.activity_heatmap.wed')).to eq('Mer')
      expect(I18n.t('insights.activity_heatmap.fri')).to eq('Ven')
      expect(I18n.t('insights.activity_streak.current')).to eq('Série actuelle')
      expect(I18n.t('insights.activity_streak.day', count: 1)).to eq('jour')
      expect(I18n.t('insights.activity_streak.day', count: 2)).to eq('jours')
      expect(I18n.t('insights.movement_wellness.sedentary_vs_active')).to eq('ACTIF VS SÉDENTAIRE')
      expect(I18n.t('insights.movement_wellness.active_vs_sedentary')).to eq('actif vs sédentaire')
      expect(I18n.t('map.maplibre.settings_panel.render_map_as_a_3d_globe_requires_page_reload'))
        .to include('nécessite de recharger la page')
      expect(I18n.t('map.maplibre.settings_panel.building_footprints')).to eq('Empreintes des bâtiments')
      expect(I18n.t('map.maplibre.settings_panel.background')).to eq('Arrière-plan')
      expect(I18n.t('notifications.index.mark_all_as_read')).to eq('Marquer toutes comme lues')
      expect(I18n.t('notifications.index.delete_all')).to eq('Tout supprimer')
      expect(I18n.t('places.drawer.avg_dwell')).to eq('durée moyenne de présence')
      expect(I18n.t('helpers.stats_comparison.same_as_previous_month'))
        .to eq('Identique au mois précédent')
      expect(I18n.t('map.residency.show.points_need_reverse_geocoding_to_detect_countries'))
        .to include('un géocodage inverse')
      expect(I18n.t('map.timeline_feeds.visit_entry.delete_this_visit_your_location_points_stay'))
        .to start_with('Voulez-vous supprimer cette visite ?')
      expect(I18n.t('settings.background_jobs.index.start_reverse_geocoding'))
        .to eq('Démarrer le géocodage inverse')
      expect(I18n.t('settings.background_jobs.index.continue_reverse_geocoding'))
        .to eq('Poursuivre le géocodage inverse')
      expect(I18n.t('share_links.hubs.shared_list.revoke_this_link_it_will_stop_working_immediately'))
        .to start_with('Voulez-vous révoquer ce lien ?')
      expect(I18n.t('users_mailer.archival_approaching.your_data_history_is_filling_up'))
        .to eq('Votre historique de localisation approche de sa limite')
    end
  end

  it 'localizes trip, insight, badge, and bulk-action plural copy' do
    I18n.with_locale(:fr) do
      expect(I18n.t('trips.trip.country_count', count: 1)).to eq('1 pays')
      expect(I18n.t('trips.trip.country_count', count: 2)).to eq('2 pays')
      expect(I18n.t('insights.location_clusters.visit_count', count: 1)).to eq('visite')
      expect(I18n.t('insights.location_clusters.visit_count', count: 2)).to eq('visites')
      expect(I18n.t('insights.top_visited_locations.visit_count', count: 1)).to eq('visite')
      expect(I18n.t('insights.top_visited_locations.visit_count', count: 2)).to eq('visites')
      expect(I18n.t('controllers.visits.bulk_updated.confirmed', count: 1)).to eq('1 visite confirmée.')
      expect(I18n.t('controllers.visits.bulk_updated.confirmed', count: 2)).to eq('2 visites confirmées.')
      expect(I18n.t('controllers.visits.bulk_updated.declined', count: 2)).to eq('2 visites refusées.')
      expect(I18n.t('controllers.visits.visit_updated.confirmed')).to eq('Visite confirmée.')
      expect(I18n.t('controllers.visits.visit_updated.declined')).to eq('Visite refusée.')

      html = ApplicationController.render(partial: 'map/timeline_feeds/suggestions_badge', locals: { count: 2 })
      badge = Nokogiri::HTML.fragment(html).at_css('.map-button-cluster__badge')
      expect(badge['aria-label']).to eq('2 visites à vérifier')
      expect(badge['title']).to eq('2 visites à vérifier')
    end

    trip_source = Rails.root.join('app/views/trips/_trip.html.erb').read
    location_source = Rails.root.join('app/views/insights/_location_clusters.html.erb').read
    top_locations_source = Rails.root.join('app/views/insights/_top_visited_locations.html.erb').read

    expect(trip_source).not_to include("'country'.pluralize")
    expect(location_source).not_to include("'visit'.pluralize")
    expect(top_locations_source).not_to include("'visit'.pluralize")
  end

  it 'uses clear French confirmations and progress labels' do
    I18n.with_locale(:fr) do
      expect(I18n.t('shared_links.modal_active.revoke_this_link_it_will_stop_working_immediately'))
        .to start_with('Voulez-vous révoquer ce lien ?')
      expect(I18n.t('visits.buttons.delete_this_visit_your_location_points_stay'))
        .to eq('Voulez-vous supprimer cette visite ? Vos points de localisation resteront.')
      expect(I18n.t('places.drawer.delete_this_place_this_cannot_be_undone'))
        .to eq('Voulez-vous supprimer ce lieu ? Cette action est irréversible.')
      expect(I18n.t('statuses.deleting')).to eq('Suppression en cours')
      expect(I18n.t('javascript.map_controls.toggle_footer')).to eq('Afficher/masquer le pied de page')
      expect(I18n.t('javascript.map_controls.toggle_panel')).to eq('Afficher/masquer le panneau')
      expect(I18n.t('javascript.map_controls.toggle_visits_drawer'))
        .to eq('Afficher/masquer le panneau des visites')
      expect(I18n.t('map.onboarding_modal.load_sample_location_data_3_days_in_berlin_to_see'))
        .to include('voir à quoi votre carte pourrait ressembler', 'les supprimer à tout moment')
      expect(I18n.t('controllers.exports.export_was_successfully_initiated_please_wait_until_it_s_finished'))
        .to eq("L'exportation a été lancée. Veuillez patienter jusqu'à sa fin.")
      expect(I18n.t('controllers.exports.export_failed_to_initiate_please_try_again'))
        .to eq("Impossible de lancer l'exportation. Réessayez.")
      expect(I18n.t('javascript.map_info.place_name_locked'))
        .to include('ce lieu, il', 'Renommez-le')
      expect(I18n.t('controllers.visits.redetections.re_detect_ran_recently_try_again_in_an_hour'))
        .to start_with('Une redétection a été exécutée récemment.')
      expect(I18n.t('controllers.visits.redetections.re_detection_queued_we_ll_notify_you_when_it_finishes'))
        .to start_with("Redétection mise en file d'attente.")
      tls_warning_key = 'settings.integrations.index.' \
                        'disabling_ssl_verification_makes_your_connection_vulnerable_to_man_in'
      expect(I18n.t(tls_warning_key))
        .to include("attaques de l'homme du milieu", 'certificats auto-signés auxquels vous faites confiance')
      expect(I18n.t('map.maplibre.webgl_error.map_v1')).to eq('/map/v1')
      expect(I18n.t('layouts.shared.self_hostable')).to eq('Auto-hébergeable')
      expect(I18n.t('layouts.shared.dawarich_turns_your_own_location_history_into_maps_worth_sharing'))
        .to include('logiciel libre et auto-hébergeable', 'contrôle de vos données')
      expect(I18n.t('map.timeline_feeds.calendar.has_suggested_visits'))
        .to eq('Contient des visites suggérées')
      expect(I18n.t('posters.studio.server_rendered_posters_from_save_to_gallery_they_stay_here'))
        .to include('elles restent ici')
      expect(I18n.t('javascript.family.sharing_since', date: 'hier', count: 2))
        .to include("2 jours d'historique")
      expect(I18n.t('models.point.already_has_a_point_at_this_location_and_time_for'))
        .to eq('possède déjà un point à cet emplacement et à cette heure pour cet utilisateur')

      api_import_error = I18n.t('controllers.api.v1.imports.an_error_occurred_while_processing_the_import')
      hexagon_error = I18n.t('controllers.api.v1.maps.hexagons.failed_to_generate_hexagon_grid')
      thumbnail_error = I18n.t('controllers.api.v1.photos.failed_to_fetch_thumbnail')
      expect(api_import_error).to include("lors du traitement de l'importation")
      expect(hexagon_error).to eq('La génération de la grille hexagonale a échoué.')
      expect(thumbnail_error).to eq('La récupération de la miniature a échoué.')
      expect(I18n.t('settings.maps.index.open_the_settings_panel_there_this_page_only_covers_the'))
        .to include('ouvrez-y le panneau des paramètres', "l'ancienne version V1")
      expect(I18n.t('settings.general.index.display_a_gem_icon_next_to_your_profile_to_show'))
        .to include('une icône en forme de gemme')
      expect(I18n.t('controllers.api.missing_required_parameters_join', parameters: 'lat, lon'))
        .to eq('Paramètres requis manquants : lat, lon')
      expect(I18n.t('controllers.api.points_limit_exceeded')).to eq('Limite de points dépassée')
      expect(I18n.t('controllers.api.v1.locations.invalid_coordinates_lat_must_be_90_90_lon_must_be'))
        .to include('la longitude (lon) entre -180 et 180')

      invitation_error_key = 'controllers.users.registrations.' \
                             'account_created_successfully_but_there_was_an_issue_accepting_the_2'
      expect(I18n.t(invitation_error_key))
        .to eq("Compte créé, mais un problème est survenu lors de l'acceptation de l'invitation. Réessayez.")
      expect(I18n.t('javascript.timeline.selected', count: 2)).to eq('Sélection : 2')
      expect(I18n.t('javascript.timeline.selected_with_max', count: 2, max: 100))
        .to eq('Sélection : 2 (max. 100)')
      expect(I18n.t('families.show.family_at_capacity', count: 5, max: 5))
        .to eq('Famille complète (5/5 membres)')
      expect(I18n.t('javascript.visits.confirmed_count', count: 1)).to eq('1 visite confirmée')
      expect(I18n.t('javascript.visits.deleted_count', count: 1)).to eq('1 visite supprimée')
      expect(I18n.t('javascript.visits.bulk_status_updated.confirmed', count: 2))
        .to eq('2 visites confirmées')
      expect(I18n.t('javascript.visits.status_updated.declined')).to eq('Visite refusée')
    end
  end

  it 'clearly explains full-history visit replacement before confirmation' do
    I18n.with_locale(:fr) do
      explanation = I18n.t(
        'settings.visits.redetect_panel.replaces_all_suggested_visits_across_your_entire_history_with_fresh'
      )
      lite_limit = I18n.t('settings.visits.redetect_panel.on_the_lite_plan_re_detection_covers_your_visible_12')

      expect(explanation).to include("d'une nouvelle détection", 'petits comptes', 'historiques')
      expect(explanation).not_to match(/détections fraîches|comptes petits|histoires/)
      expect(lite_limit).to include('redétection', '12 derniers mois')
      expect(lite_limit).not_to include('re-détective')
    end
  end

  it 'uses localized plural nouns in the activity-streak view' do
    source = Rails.root.join('app/views/insights/_activity_streak.html.erb').read

    expect(source).to include("t('.day', count: @activity_heatmap.current_streak)")
    expect(source).to include("t('.day', count: @activity_heatmap.longest_streak)")
    expect(source).not_to include("'day'.pluralize")
  end

  it 'pluralizes French visit-redetection completion copy' do
    key = 'jobs.visits.full_history_redetect_job.visits_created_visits_across_ok_months_of_size_months_size'
    variables = { visits: '3 visites', ok_months: '2 mois', months: '4 mois' }

    I18n.with_locale(:fr) do
      expect(I18n.t(key, **variables, count: 1)).to include('1 mois a échoué')
      expect(I18n.t(key, **variables, count: 2)).to include('2 mois ont échoué')
    end
  end

  it 'varies every localized insights and statistics fragment cache by locale' do
    insights_index = Rails.root.join('app/views/insights/index.html.erb').read
    insights_details = Rails.root.join('app/views/insights/details.html.erb').read
    stats_index = Rails.root.join('app/views/stats/index.html.erb').read

    expect(insights_index).to include('[current_user.id, I18n.locale, "insights"')
    expect(insights_details).to include('[current_user.id, I18n.locale, "insights"')
    expect(stats_index.scan('[current_user.id, I18n.locale').size).to eq(2)
  end

  it 'renders the live-location privacy warning as one complete sentence' do
    html = I18n.with_locale(:fr) do
      ApplicationController.render(
        partial: 'shared_links/modal_live_create_form',
        locals: { paths: { create: '/share' }, close_path: '/' }
      )
    end
    document = Nokogiri::HTML.fragment(html)
    warning = document.at_css('.alert-warning')

    expect(warning.text.squish).to eq(
      'Toute personne disposant du lien pourra voir votre emplacement actuel en temps réel ' \
      "jusqu'à l'expiration ou la révocation du lien."
    )
    expect(warning.at_css('strong').text).to eq('emplacement actuel en temps réel')
  end

  it 'uses list semantics only once in the archival upgrade email' do
    user = create(:user)

    I18n.with_locale(:fr) do
      mail = UsersMailer.with(user:).archival_approaching
      html_items = Nokogiri::HTML(mail.html_part.body.to_s).css('ul li').map { |item| item.text.squish }
      text_body = mail.text_part.body.to_s

      expect(html_items).not_to be_empty
      expect(html_items).to all(satisfy { |item| !item.start_with?('-') })
      expect(text_body).to include('- Historique entièrement consultable')
    end
  end

  it 'composes the subscription validity duration in natural French order' do
    I18n.with_locale(:fr) do
      duration = ActionController::Base.helpers.distance_of_time_in_words(Time.current, 2.months.from_now)
      copy = [I18n.t('settings.subscriptions.index.your_subscription_will_be_valid_for_the_next'), duration].join(' ')

      expect(copy).to eq('Votre abonnement restera valable pendant encore 2 mois')
    end
  end

  it 'provides clear account-link recovery instructions for unverified providers' do
    I18n.with_locale(:fr) do
      apple = I18n.t('controllers.api.v1.auth.apple.apple_has_not_verified_this_email_sign_in_with_password')
      google = I18n.t('controllers.api.v1.auth.google.google_has_not_verified_this_email_sign_in_with_password')

      expect(apple).to include('associez Apple depuis les paramètres de votre compte')
      expect(google).to include('associez Google depuis les paramètres de votre compte')
    end
  end
end
