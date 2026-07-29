# Architekturübersicht: Dawarich Immich Tags

## Projektübersicht

Dieses Repository ist eine Entwicklungsvariante von Dawarich mit zusätzlichen Funktionen rund um Immich-Integration, Fotoanzeige und Nachbearbeitung vorhandener Bilder.

Der Kern der Anwendung ist eine Ruby-on-Rails-Anwendung mit:

- Standortverfolgung und -visualisierung
- Import und Export von Geodaten
- Kartenansichten mit mehreren Layern
- Trips, Visits, Areas und Places
- Foto- und Medienintegration mit Immich und Photoprism
- Hintergrundverarbeitung über Sidekiq
- PostgreSQL mit PostGIS als Datenbank
- Redis als Queue- und Cache-Backend

Der Schwerpunkt dieses Repositories liegt auf der Verarbeitung von Fotos aus Immich und der Nachbearbeitung bestehender Bilder, also nicht nur neu hinzukommender Medien.

## Verzeichnisstruktur

Die wichtigste Ordnung im Repository ist:

```text
app/
  controllers/      # HTTP-Controller, inklusive API-Controller
  models/           # ActiveRecord-Modelle und Concern-Module
  services/         # Business-Logik und externe Integrationen
  jobs/             # ActiveJob-/Sidekiq-Jobs
  views/            # ERB-Templates und UI-Teile
  javascript/       # Stimulus-Controller und Frontend-Logik
  serializers/      # API-Serialisierer
  policies/         # Pundit-Policies
  queries/           # Datenbankabfragen
  mailers/           # Mailer
  channels/          # ActionCable-Kanäle

config/
  routes.rb         # Routing
  database.yml      # DB-Konfiguration
  sidekiq.yml       # Sidekiq-Queues und Concurrency
  schedule.yml      # Cron-/Job-Zeitpläne
  initializers/     # Initialisierer und globale Konfiguration

db/
  migrate/          # Datenbankmigrationen
  schema.rb         # Aktueller Schema-Stand

docker/
  docker-compose.yml
  Dockerfile
  web-entrypoint.sh
  sidekiq-entrypoint.sh

spec/
  services/         # Service-Tests
  requests/         # Request-/API-Tests
  models/           # Modell-Tests
  jobs/             # Job-Tests
  regressions/      # Regressionsspezifika
```

## Datenfluss

Die typische Verarbeitung folgt mehreren Schritten:

1. Ein Nutzer oder ein Import erzeugt Daten, meist Punkte oder Importdateien.
2. Imports werden als ActiveRecord-Modelle gespeichert.
3. Ein Import- oder Verarbeitungsjob wird asynchron über Sidekiq gestartet.
4. Services verarbeiten Daten, beispielsweise:
   - Geodaten aus Importdateien
   - Reverse Geocoding
   - Foto-Metadaten aus Immich oder Photoprism
   - Statistik- und Visit-Berechnungen
5. Die Ergebnisse werden in der Datenbank gespeichert und in der UI dargestellt.

Für Immich ist der relevante Datenfluss besonders sichtbar:

1. Der Benutzer hat Immich-Zugangsdaten konfiguriert.
2. Ein Service fragt die Immich-Such-API nach Fotos und Metadaten ab.
3. Für Fotos ohne Geodaten werden mögliche Treffer mit vorhandener Dawarich-Lokationshistorie verglichen.
4. Die gefundenen Koordinaten können entweder als Vorschläge angezeigt oder direkt an Immich zurückgeschrieben werden.

## Controller

Die Controller sind in zwei Hauptbereiche unterteilt:

- Web-Controller unter app/controllers für Views und Standard-Interaktionen
- API-Controller unter app/controllers/api und app/controllers/api/v1

Wichtige Controller sind unter anderem:

- ApplicationController und ApiController als Basis-Controller
- Imports-, Points-, Trips-, Visits-, Stats-, Places- und Families-Controller für die Hauptfunktionen
- Api::V1::PhotosController für Foto-Suche und Thumbnails
- Api::V1::Immich::EnrichController für Scan und Enriching von Immich-Fotos

Besonderheiten:

- ApiController behandelt Authentifizierung über API-Key, Plan-Checks und Rate-Limits.
- Die Immich-Enrich-API ist nur für Benutzer mit ausreichender API-/Plan-Berechtigung verfügbar.

## Models

Die Anwendung verwendet ein klassisches ActiveRecord-Modell-Set mit zahlreichen Domänenmodellen.

Wichtige Modelle:

- User: zentrale Nutzer-Entität, Authentifizierung, Einstellungen, Plan-Status, Integrationskonfiguration
- Point: einzelne Standortpunkte mit PostGIS-Geometry (lonlat), Zeitstempel und Metadaten
- Import: Import-Operationen von Dateien oder externen Quellen
- Track, Trip, Visit, Area, Place: Reise- und Ortslogik
- Tag und Tagging: allgemeine Tagging-Funktionalität
- Notification, Note, SharedLink, Family, Flight: zusätzliche Domänenobjekte

Besondere Modelltechnik:

- Punkte sind mit PostGIS über die Column lonlat gespeichert.
- Viele Modelle arbeiten mit Concerns, beispielsweise PlanScopable für Plan-gesteuerte Sichtbarkeit und Filter.
- Import-Modelle verwenden Active Storage, um importierte Dateien zu speichern.

## Services

Services kapseln die komplexe Business-Logik und externe Anbindungen.

### Immich-relevante Services

- Immich::ImportGeodata: holt Immich-Metadaten und baut daraus einen Import
- Immich::RequestPhotos: fragt die Immich-API nach Fotos und Metadaten ab
- Immich::EnrichScan: scannt Fotos ohne GPS-Daten und sucht passende Dawarich-Punkte
- Immich::EnrichPhotos: schreibt gefundene Koordinaten zurück an Immich
- Immich::ConnectionTester: testet die Immich-Verbindung
- Immich::Tags: liest Immich-Tags über die Immich-API

### Weitere wichtige Services

- Photos::Search und Photos::Thumbnail: Foto-Suche und Thumbnail-Resolution für Immich/Photoprism
- Imports::Create und Imports::SourceDetector: Import- und Quelle-Erkennung
- Users::ExportData und Users::ImportData: Export/Import von Benutzerdaten
- ReverseGeocoding::...-Services: Geocoding und Reverse-Geocoding
- Settings::Update: Aktualisierung von Nutzer- und Integrations-Einstellungen

Die Services sind der zentrale Ort für API-Abfragen an externe Systeme und für die Transformation von Rohdaten in das Dawarich-Datenmodell.

## Jobs

Die Anwendung nutzt ActiveJob mit Sidekiq als Adapter.

Wichtige Job-Kategorien:

- Import-Jobs: Import::ProcessJob, Import::ImmichGeodataJob, Import::PhotoprismGeodataJob
- Geocoding-Jobs: ReverseGeocodingJob
- Statistik- und Reise-Jobs: bulk stats, visits, trips, posters, digests
- Nutzer- und Wartungs-Jobs: app version checks, stale jobs recovery, archival jobs

Besonderheiten:

- Die Queue-Konfiguration in config/sidekiq.yml organisiert Jobs in verschiedene Queues, darunter imports, reverse_geocoding, stats, trips, archival und others.
- Import- und Verarbeitungsjobs sind zentral über EnqueueBackgroundJob erreichbar.

## API-Anbindungen

### Immich

Die Umsetzung ist konkret im Repository vorhanden:

- Immich-Such-API über /api/search/metadata
- Immich-Tags-API über /api/tags
- Immich-Asset-Update über /api/assets/:id

Die Anbindung verwendet HTTP-Requests mit HTTParty und ist an die vorhandenen Safe-Settings des Nutzers gekoppelt.

### Photoprism

Die Anwendung enthält ebenfalls eine eigene Photoprism-Integration, etwa für Import und Foto-Suche, allerdings ist die Immich-Erweiterung im aktuellen Fokus dieses Repositories.

### Weitere externe Systeme

- Geocoder/Photon-Integration für Reverse Geocoding
- Sentry, PostHog, Prometheus-/Monitoring-Integration
- AWS S3-Integration über Active Storage-Konfiguration

## Frontend-Komponenten

Das Frontend verwendet Hotwire-Elemente und Stimulus, zusätzlich zu MapLibre/Leaflet-Integration.

### Grundprinzipien

- Turbo/Stimulus statt umfangreicher benutzerdefinierter JavaScript-Architekturen
- Importmap-basierte Frontend-Integration
- Tailwind CSS und DaisyUI für die UI

### Relevante Frontend-Bausteine

- Kartenansicht und Karten-Panel aus app/views/map und app/javascript
- Stimulus-Controller für Map-Interaktionen, Uploads und spezielle Panels
- Immich-Enrich-UI, eingebunden im Karten-Panel über einen eigenen Controller
- Foto-Thumbnail- und Foto-Suche über API-Endpunkte

Die Immich-fokussierte UI ist aktuell im Karten-Settings-Panel sichtbar und erlaubt:

- Scan nach Fotos ohne GPS-Daten
- Trefferliste mit Dateinamen, Zeitstempel und Koordinaten
- Auswahl von Treffern
- Direkte Übertragung der Koordinaten back to Immich

## Datenbank

Die Anwendung verwendet PostgreSQL mit PostGIS.

Wichtige Merkmale:

- PostGIS-Erweiterung ist aktiviert
- Punkte speichern Geometrie in der Spalte lonlat
- Geographische Abfragen und Indizes sind Teil der Datenbankstruktur
- Import- und Export-Modelle haben eigene Tabellen und Statusfelder
- Active Storage wird für Dateianhänge verwendet

Die Schema-Datei zeigt unter anderem Tabellen für:

- users, points, imports, tracks, trips, visits, areas, places, tags, taggings, stats, exports, families und notifications

Die Datenbank ist damit nicht nur ein Speicher für Standorte, sondern auch für Import- und Analysezustände sowie für die Foto- und Medienintegration.

## Docker

Die Anwendung ist für den Betrieb mit Docker Compose ausgelegt.

Im Compose-Setup sind mindestens diese Dienste vorhanden:

- dawarich_app: Webanwendung auf Port 3000
- dawarich_sidekiq: Hintergrundprozess-Container
- dawarich_db: PostgreSQL mit PostGIS
- dawarich_redis: Redis

Die Container verwenden gemeinsame Volumes für:

- öffentliche Dateien
- Imports und Watch-Ordner
- Storage
- Datenbankdaten

Die Container sind in der Compose-Datei mit Healthchecks und Abhängigkeiten verbunden, damit Web- und Sidekiq-Prozesse zuverlässig starten.

## Hintergrundprozesse

Hintergrundprozesse spielen eine zentrale Rolle in der Anwendung.

Aktuell relevant sind:

- Import-Verarbeitung
- Reverse Geocoding
- Statistik-/Visit-/Trip-Berechnungen
- Poster-/Digest-Generierung
- Archivierungs- und Wartungsjobs

Diese Prozesse laufen über Sidekiq und sind in config/sidekiq.yml in separate Queues organisiert.

## Besonderheiten des Projekts

### Immich als Erweiterung statt nur als Importquelle

Das Projekt verfolgt nicht nur den klassischen Import, sondern erweitert das Verhalten um eine bestehende Bildnachbearbeitung. Das ist ein wesentlicher Unterschied zu einer einfachen Immich-Integration.

### Verarbeitung vorhandener Bilder

Ein expliziter Projektgrundsatz ist, bestehende Bilder nachträglich verarbeiten zu können. Das ist im aktuellen Code bereits in der Enrich-Logik sichtbar.

### Plan- und Zugriffskontrolle

Die Anwendung enthält eine eigene Plan-Logik, die je nach Benutzerstatus und Plan die Sichtbarkeit von Daten und die Verfügbarkeit von Funktionen steuert.

### PostGIS als zentrales Geodaten-Feature

Die Geodaten sind nicht nur als einfache Felder gespeichert, sondern sind in einem räumlichen Datenmodell mit PostGIS angelegt.

### Testabdeckung

Das Repository enthält bereits umfangreiche Specs für Services, Requests und Jobs. Die Immich-Erweiterung ist ebenfalls mit Tests abgesichert.
