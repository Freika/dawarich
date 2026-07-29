# Projektdateien und Verzeichnisse

## Überblick

Dieses Repository enthält eine Ruby-on-Rails-Anwendung für die Erfassung, Analyse und Darstellung von Standortverläufen sowie zusätzliche Funktionen rund um Immich- und Fotoverarbeitung.

Die wichtigsten Bereiche sind:

- app/ für Anwendungslogik, Controller, Models, Services, Jobs und Views
- config/ für Rails-, Sidekiq-, Routing- und Initialisierungs-Konfiguration
- db/ für Migrations und Schema
- docker/ für die Docker-Compose- und Container-Setup-Dateien
- spec/ für Tests

## Wichtige Verzeichnisse

### app/

Das Kernverzeichnis der Anwendung.

- app/controllers/: HTTP- und API-Controller
- app/models/: ActiveRecord-Modelle und Concerns
- app/services/: Business-Logik und externe Anbindungen wie Immich, Photoprism, Import- und Geocoding-Services
- app/jobs/: Hintergrundjobs für Importe, Geocoding, Stats, Trips, Visits und Wartung
- app/views/: ERB-Templates und UI-Bausteine
- app/javascript/: Stimulus-Controller und Frontend-Logik, inklusive Karten- und Immich-Integration
- app/serializers/: Serialisierer für API-Antworten
- app/policies/: Pundit-Policies
- app/queries/: Datenbankabfragen
- app/mailers/: Mailer
- app/channels/: ActionCable-Kanäle

### config/

Enthält die zentrale Konfiguration der Rails-Anwendung.

- config/routes.rb: Routen für Web- und API-Endpoints
- config/application.rb: Rails-Anwendungsinitialisierung
- config/database.yml: Datenbankkonfiguration
- config/sidekiq.yml: Sidekiq-Queues und Concurrency
- config/schedule.yml: Zeitpläne für wiederkehrende Jobs
- config/initializers/: Initialisierer für Auth, Middleware, Integrationen und globale Einstellungen

### db/

Enthält das Datenbankschema und Migrationsdateien.

- db/schema.rb: aktueller Schema-Stand
- db/migrate/: alle Migrationsdateien

### docker/

Enthält die Docker-Umgebung für die Anwendung.

- docker/docker-compose.yml: Compose-Setup mit Web-, Sidekiq-, DB- und Redis-Containern
- docker/Dockerfile: Image-Definition
- docker/web-entrypoint.sh und docker/sidekiq-entrypoint.sh: Startskripte für die Container

### spec/

Enthält die Testsuite.

- spec/services/: Service-Tests
- spec/requests/: API- und Request-Tests
- spec/models/: Modell-Tests
- spec/jobs/: Job-Tests
- spec/regressions/: Regressions- und Sonderfälle

## Wichtige Einzeldateien

### Root-Dateien

- Gemfile: Ruby-Gem-Abhängigkeiten
- package.json: JavaScript- und Frontend-Abhängigkeiten
- README.md: allgemeine Projektbeschreibung und Einstieg
- DEVELOPMENT.md: Entwicklungs- und Test-Anleitung
- Procfile.dev: lokale Entwicklungsprozesse für die Web-App
- Procfile: Produktionsprozesse
- Rakefile: Rake-Aufgaben
- config.ru: Rack-Startpunkt der Anwendung

### Anwendungslogik

- app/controllers/api_controller.rb: Basisklasse für API-Controller mit Authentifizierung, Plan-Prüfungen und Rate-Limits
- app/models/user.rb: Benutzer- und Integrationslogik
- app/models/point.rb: einzelne Standortpunkte und Spatial-Logik
- app/models/import.rb: Import-Entität und Import-Status
- app/services/immich/import_geodata.rb: Import von Immich-Metadaten
- app/services/immich/enrich_scan.rb: Scan von Immich-Fotos ohne Geodaten
- app/services/immich/enrich_photos.rb: Schreiben von Geodaten zurück nach Immich
- app/services/photos/search.rb: Foto-Suche über Immich/Photoprism
- app/jobs/reverse_geocoding_job.rb: Reverse-Geocoding-Job
- app/javascript/controllers/maps/immich_enrich_controller.js: UI-Controller für den Immich-Enrich-Workflow

## Zweck der wichtigsten Bausteine

- Controller steuern HTTP- und API-Anfragen.
- Models modellieren Domänenobjekte und Datenbankbeziehungen.
- Services kapseln komplexe Logik, insbesondere externe API-Anbindungen.
- Jobs ermöglichen asynchrone Verarbeitung über Sidekiq.
- Views und Stimulus-Controller liefern die Nutzeroberfläche.
- Tests sichern die bestehende Funktionalität.
