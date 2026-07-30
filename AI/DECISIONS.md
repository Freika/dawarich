# Dokumentierte Entscheidungen und Ableitungen aus dem Code

## Einleitung

Diese Datei dokumentiert nur Entscheidungen, die sich eindeutig aus dem vorhandenen Code, der Projekt-Dokumentation oder der Repository-Historie ableiten lassen. Unsichere Punkte sind bewusst als „noch zu klären“ markiert.

## Feststehende Entscheidungen

### 1. Die Anwendung ist als Rails-Anwendung mit Sidekiq aufgebaut

Belegt durch:

- Gemfile mit Rails- und Sidekiq-Abhängigkeiten
- config/application.rb mit ActiveJob-Queue-Adapter :sidekiq
- config/sidekiq.yml mit definierten Queues

### 2. PostgreSQL mit PostGIS ist Teil der Datenbankarchitektur

Belegt durch:

- db/schema.rb mit enable_extension "postgis"
- docker/docker-compose.yml mit einem PostGIS-Container
- app/models/point.rb, die Geometrie über lonlat verarbeitet

### 3. Immich ist als separate externe Bildquelle integriert

Belegt durch:

- app/services/immich/* für Import, Request, Enriching und Tag-Abfrage
- app/controllers/api/v1/immich/enrich_controller.rb
- app/javascript/controllers/maps/immich_enrich_controller.js
- Projekt-Dokumentation in AGENTS.md und AI/PROJECT.md

### 4. Die Anwendung verfolgt nicht nur Import, sondern auch Nachbearbeitung vorhandener Bilder

Belegt durch:

- AI/PROJECT.md mit dem Ziel, bestehende Bilder nachträglich verarbeiten zu können
- app/services/immich/enrich_scan.rb und app/services/immich/enrich_photos.rb
- die UI im Karten-Panel für Scan und Enriching

### 5. Hintergrundverarbeitung ist ein zentraler Teil der Architektur

Belegt durch:

- app/jobs/ mit zahlreichen Job-Klassen
- config/sidekiq.yml mit separaten Queues
- Import- und Geocoding-Jobs als asynchrone Verarbeitung

### 6. Die Anwendung verwendet Hotwire/Stimulus für Frontend-Interaktionen

Belegt durch:

- package.json mit @hotwired/turbo-rails und stimulus-rails
- app/javascript/application.js
- Stimulus-Controller im Verzeichnis app/javascript/controllers

### 7. Fotoquellen in neuen Shared Links werden explizit ausgewählt

Über die neue Oberfläche erzeugte Shared Links speichern neben `show_photos`
die beiden Einstellungen `show_photoprism` und `show_immich`.

- Sind beide Einstellungen `false`, werden keine Fotos geladen.
- PhotoPrism kann ohne Immich-spezifische Filter über den bisherigen Suchpfad
  verwendet werden.
- Immich kann optional auf ein Album eingeschränkt werden. Eine leere Album-ID
  bedeutet „alle Bilder“ und verwendet die bisherige ungefilterte Immich-Suche.
- Beide Quellen können gleichzeitig aktiviert werden.
- Bei bestehenden Shared Links ohne die beiden neuen Schlüssel bleibt die
  bisherige automatische Auswahl aller konfigurierten Integrationen erhalten.

Belegt durch:

- app/services/shared_links/photo_sources.rb
- app/services/photos/search.rb
- app/controllers/concerns/share_links/managable.rb
- app/views/shared_links/_immich_shared_link_fields.html.erb

## Noch zu klären

Die folgenden Punkte sind im Repository nicht vollständig belegt und sollten bei Bedarf separat geprüft werden:

- Die genaue Branch- und Release-Strategie des Projekts
- Die vollständige historische Abgrenzung zum Upstream-Dawarich
- Die genaue Ausprägung aller Immich-Features über alle Branches und Releases hinweg
- Die vollständige Liste aller Sonderfälle, die in der Git-Historie dokumentiert sind
## Immich-Deep-Link im Foto-Overlay

Im Dawarich-Share-Dialog werden albumgebundene öffentliche Immich-Shared-Links
über `GET /api/shared-links` geladen. Shared-Link-ID und Slug sowie ID und Name
des eingebetteten Albums werden gemeinsam in den Share-Einstellungen
gespeichert. Die Album-ID begrenzt weiterhin die Immich-Fotosuche. Im
Vollbild-Overlay verweist das Immich-Logo ausschließlich auf das angezeigte
Asset innerhalb der öffentlichen Freigabe (`/s/:slug/photos/:asset_id`).
Direkte Links auf `/photos/:id` oder `/albums/:id` und entsprechende Fallbacks
sind aus Sicherheitsgründen nicht zulässig. Beim Anzeigen des Overlays erfolgt
keine zusätzliche Immich-API-Anfrage. Alte Shares ohne gespeicherten
Shared-Link-Slug rendern keinen Immich-Link.
