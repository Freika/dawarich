# AGENTS.md

## Zweck dieser Datei

Diese Datei ist der zentrale Einstiegspunkt für KI-gestützte Entwicklungswerkzeuge wie OpenAI Codex, GitHub Copilot, Claude Code oder ähnliche Agenten.

Bevor du Änderungen an diesem Repository vornimmst, lies mindestens:

1. `AI/README.md`
2. `AI/PROJECT.md`

## Projektüberblick

Dieses Repository enthält eine Entwicklungsvariante von Dawarich mit Erweiterungen rund um die Immich-Integration und die Darstellung bzw. Nachbearbeitung vorhandener Bilder.

Der aktuelle Projektordner heißt sinngemäß:

```text
dawarich-immich-tags-dev
```

Technischer Kontext:

- Ruby on Rails
- Sidekiq für Hintergrundjobs
- PostgreSQL/PostGIS
- Redis
- Docker und Docker Compose
- Immich als externe Bildquelle
- Photon als lokale Reverse-Geocoding-Instanz

## Arbeitsregeln für KI-Agenten

### Vor jeder Änderung

- Untersuche zuerst den vorhandenen Code und die bestehende Struktur.
- Lies die einschlägigen Dateien vollständig, bevor du Änderungen vorschlägst.
- Suche nach vorhandenen Services, Jobs, Modellen, Helpern und Tests, bevor du neue Strukturen anlegst.
- Vermeide parallele oder doppelte Implementierungen.
- Erhalte vorhandenes Verhalten, sofern die Aufgabe nicht ausdrücklich eine Änderung verlangt.

### Änderungen

- Bevorzuge kleine, nachvollziehbare Änderungen.
- Änderungen am Dawarich-Kern nur dann, wenn keine saubere Erweiterung möglich ist.
- Hintergrundverarbeitung gehört nach Möglichkeit in Sidekiq-Jobs oder vorhandene Jobstrukturen.
- Keine Zugangsdaten, API-Schlüssel, Passwörter oder privaten URLs in Git eintragen.
- Konfigurationen über Umgebungsvariablen oder bestehende Konfigurationsmechanismen vornehmen.
- Bestehende Bilder müssen ausdrücklich berücksichtigt werden; eine Lösung darf nicht nur neu importierte Bilder bearbeiten, wenn die Aufgabe auch Altbestand umfasst.

### Tests und Prüfung

- Bestehende Tests zuerst ansehen.
- Neue oder geänderte Logik möglichst mit Tests absichern.
- Nach Änderungen mindestens die betroffenen Tests ausführen.
- Bei Docker- oder Rails-Änderungen die tatsächlich verwendeten Container- und Servicenamen prüfen.
- Keine erfolgreiche Ausführung behaupten, wenn sie nicht nachweislich getestet wurde.

### Dokumentation

- Relevante technische Entscheidungen in den Dateien unter `AI/` ergänzen.
- Neue Umgebungsvariablen dokumentieren.
- Manuelle Migrations-, Start- oder Reparaturschritte mit konkreten Befehlen dokumentieren.
- Bei Workarounds klar kennzeichnen, ob es sich um eine vorläufige oder dauerhafte Lösung handelt.

## Bekannte Rahmenbedingungen

- Dawarich läuft in Docker.
- Die Anwendung verwendet getrennte Container für Webanwendung und Sidekiq.
- Immich ist bereits vorhanden und erreichbar.
- Photon läuft lokal und soll nicht öffentlich veröffentlicht werden.
- Das Projekt soll bestehende Bilder verarbeiten können, nicht ausschließlich neu hinzukommende Bilder.
- Bei Shared-Links wurde ein Zusammenhang zwischen negativen Tagesdistanzen und fehlenden Bildern beobachtet. Dieser Fehler wurde separat untersucht und upstream gemeldet.

## Kommunikationsstil bei Arbeiten im Repository

Bei Vorschlägen oder Änderungen:

1. Zuerst kurz erklären, was gefunden wurde.
2. Dann den konkreten Änderungsvorschlag nennen.
3. Die betroffenen Dateien aufführen.
4. Die auszuführenden Befehle vollständig angeben.
5. Abschließend beschreiben, wie das Ergebnis geprüft werden kann.

Vermeide unvollständige Befehlsfragmente und unnötige Copy-and-Paste-Ketten. Bevorzuge vollständige, direkt ausführbare Blöcke.
