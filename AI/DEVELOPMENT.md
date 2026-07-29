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
