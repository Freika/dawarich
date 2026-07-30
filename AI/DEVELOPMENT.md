# Entwicklungsumgebung und Arbeitsablauf

## Tatsächlich verwendete Umgebung

Das Projekt ist eine Ruby-on-Rails-Anwendung mit folgenden Kernbestandteilen:

- Ruby (die genaue Version ist in .ruby-version festgelegt)
- Rails 8.1.x
- PostgreSQL mit PostGIS
- Redis
- Sidekiq für Hintergrundjobs
- Docker Compose für die Standard-Entwicklung und den Betrieb

Die Repository-Dokumentation beschreibt zwei Hauptwege:

1. Entwicklung über Docker/Devcontainer
2. Native Installation ohne Devcontainer

## Verfügbare Start- und Testbefehle

### Lokale Entwicklung

Die Datei DEVELOPMENT.md dokumentiert die folgenden Befehle:

```bash
bundle install
bundle exec rails db:prepare
bundle exec sidekiq
bundle exec bin/dev
```

Die Prozesse aus Procfile.dev sind:

```text
web: bin/rails server -p 3000 -b ::
css: bin/rails tailwindcss:watch
```

### Produktion/Container

Die Standard-Prozesse aus Procfile sind:

```text
release: bundle exec rails db:migrate
web: bundle exec puma -C config/puma.rb
worker: bundle exec sidekiq -C config/sidekiq.yml
```

### Tests

Die vorhandene Dokumentation nennt für die Testsuite:

```bash
RAILS_ENV=test bundle exec rspec
```

## Docker-Befehle

Die Dokumentation und die Compose-Datei beschreiben den üblichen Start über Docker Compose:

```bash
docker compose -f docker/docker-compose.yml up
```

Die Compose-Umgebung enthält diese Hauptcontainer:

- dawarich_app
- dawarich_sidekiq
- dawarich_db
- dawarich_redis

## Coding-Konventionen und Qualitätswerkzeuge

### Ruby

- RuboCop ist konfiguriert über .rubocop.yml
- Die Konfiguration deaktiviert einige Default-Regeln und aktiviert die eigene Rule-Extension unter lib/rubocop/cop/dawarich/points_lat_lon_access

### JavaScript/CSS

- Biome ist für Formatierung und Linting der Frontend-Dateien konfiguriert
- Die Konfiguration ist in biome.json beschrieben

### Allgemein

- Die Projektregeln aus AGENTS.md empfehlen, vorhandene Strukturen zuerst zu prüfen, kleine Änderungen vorzunehmen und Tests zu ergänzen
- Dokumentation und Konfigurationsänderungen sollen nachvollziehbar bleiben
- Zugangsdaten und API-Schlüssel dürfen nicht im Repository gespeichert werden

## Empfohlener Arbeitsablauf

1. Relevante Dateien und vorhandene Tests prüfen, bevor Änderungen vorgenommen werden.
2. Kleine, fokussierte Änderungen bevorzugen.
3. Für Änderungen an Rails- oder Docker-Logik die tatsächlichen Service- und Container-Namen im Compose-Setup beachten.
4. Bei Änderungen an Ruby-Dateien RuboCop ausführen.
5. Bei Änderungen an JS/CSS-Dateien Biome verwenden.
6. Für funktionale Änderungen relevante Specs ergänzen oder anpassen.
7. Nach Änderungen die betroffenen Tests ausführen.

## Hinweise zur Entwicklungsumgebung

- Die Standard-Login-Daten in der Entwicklungsumgebung sind laut Dokumentation:
  - E-Mail: demo@dawarich.app
  - Passwort: safepassword
- Für lokale Tests wird dotenv verwendet, und .env.test wird automatisch geladen.
- Für Docker- oder lokale Datenbank-Setups ist PostgreSQL mit PostGIS erforderlich.

## Make-Workflow

Das Makefile im Projektstamm bildet den abgesicherten lokalen Workflow ab:

- `make testvscode` führt die Immich-/PhotoPrism-relevanten Specs im Service
  `dawarich_dev` aus. Läuft der DevContainer noch nicht, wird er inklusive
  eines nötigen Image-Builds über die `devcontainer`-Vorbedingung gestartet;
  ist er bereits aktiv, wird nichts neu gebaut. Volumes werden in keinem Fall
  erstellt oder gelöscht.
- `make review` prüft Git-Status, staged und unstaged Whitespace-Fehler,
  unerwünschte Dateien, Merge-Konfliktmarker und führt anschließend
  `make testvscode` aus.
- `make testdawarich` verlangt zuerst ein erfolgreiches `make review`, baut
  anschließend über `docker/Dockerfile` das vorhandene Image
  `dawarich-immich-tags:test` und erstellt ausschließlich `dawarich_app` und
  `dawarich_sidekiq` unter `/root/dawarich-test` neu.
- `make commit MESSAGE="..."` erstellt unabhängig vom Review-Status einen
  lokalen Zwischenstand und behält dabei seine Prüfungen auf unerwünschte
  Dateien und leere Commits bei.
- `make dawarich CONFIRM=PRODUCTION` verlangt zuerst ein erfolgreiches
  `make review` sowie einen sauberen Git-Stand und aktualisiert ausschließlich
  dieselben Anwendungsdienste unter `/root/dawarich`.

Keines der Deployment-Targets löscht Docker-Volumes oder verwendet
`docker compose down -v`.

## Mandatory review and deployment workflow

Diese Reihenfolge ist für jede Änderung verbindlich:

1. Änderung im Entwicklungsrepository implementieren.
2. Den vollständigen staged und unstaged Git-Diff untersuchen.
3. Die verpflichtende semantische KI-Codeprüfung durchführen.
4. Alle blockierenden Befunde beheben und den vollständigen Diff erneut prüfen.
5. `make review` ausführen.
6. `make testdawarich` ausführen.
7. Das Feature in der Testinstanz manuell prüfen.
8. Mit `make commit MESSAGE="..."` committen.
9. Den sauberen, committeten Stand mit
   `make dawarich CONFIRM=PRODUCTION` produktiv bereitstellen.
10. Die Produktionsinstanz manuell validieren.
11. Erst danach mit `make push` zum konfigurierten Fork pushen.

Produktion darf niemals verändert werden, bevor die semantische KI-Prüfung
und `make review` erfolgreich waren. Ein uncommitteter Working Tree darf
niemals produktiv bereitgestellt werden. Vor erfolgreicher
Produktionsvalidierung darf nicht gepusht werden. Eine erfolgreiche
RSpec-Suite ersetzt keine semantische Codeprüfung. Der KI-Assistent muss seine
Review-Befunde melden, bevor er Test- oder Deployment-Befehle vorschlägt.

Für Immich-Shared-Link-Änderungen sind in der Test- und später in der
Produktionsinstanz mindestens diese manuellen Prüfungen erforderlich:

1. Einen Dawarich-Share erstellen.
2. Einen Immich Shared Link auswählen.
3. Den Dawarich-Share ohne Anmeldung öffnen.
4. Ein Foto im Vollbild-Viewer öffnen.
5. Dem Immich-Link folgen.
6. Prüfen, dass die URL `/s/:slug/photos/:asset_id` verwendet.
7. Prüfen, dass keine angemeldete Immich-Sitzung erforderlich ist.
8. Prüfen, dass keine anderen Immich-Assets durchsucht werden können.
9. Desktop- und Mobilansicht prüfen.
10. Browser-Konsole und Anwendungslogs auf Fehler kontrollieren.
