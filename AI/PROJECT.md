# Projektbeschreibung: Dawarich Immich Tags

## Projektziel

Das Projekt erweitert eine Dawarich-Entwicklungsinstanz um Funktionen rund um die Einbindung, Zuordnung, Darstellung und Nachbearbeitung von Bildern aus Immich.

Ein wesentliches Ziel ist, nicht nur neu hinzukommende Bilder zu berücksichtigen, sondern auch bereits vorhandene Bilder nachträglich verarbeiten zu können.

## Fachlicher Hintergrund

Dawarich speichert und visualisiert Standortdaten und Reisen. Immich verwaltet die zugehörigen Fotos und Videos. Durch die Integration sollen Medien passend zu Zeitpunkten, Tagen, Reisen oder Positionen angezeigt und bei Bedarf mit zusätzlichen Informationen oder Zuordnungen versehen werden.

Die Lösung soll möglichst robust, nachvollziehbar und mit dem bestehenden Dawarich-Code kompatibel bleiben.

## Aktuelle Umgebung

Die bekannte Betriebsumgebung besteht aus:

- Dawarich als Ruby-on-Rails-Anwendung
- Sidekiq für asynchrone Verarbeitung
- PostgreSQL mit PostGIS
- Redis
- Docker Compose
- Immich als vorhandenes Medienarchiv
- lokale Photon-Instanz für Reverse Geocoding

Bekannte Compose-Dienste der laufenden Dawarich-Installation:

```text
dawarich_app
dawarich_sidekiq
dawarich_db
dawarich_redis
photon
```

Die produktive Dawarich-Installation und dieses Entwicklungsrepository sind voneinander zu unterscheiden. Änderungen im Entwicklungsrepository dürfen nicht stillschweigend als bereits produktiv installiert betrachtet werden.

## Hauptanforderungen

### Immich-Integration

- Medien aus Immich sollen anhand geeigneter Zeit- und Ortsinformationen Dawarich-Daten zugeordnet werden.
- Die bestehende Immich-Installation bleibt die führende Medienquelle.
- API-Zugriffe müssen über konfigurierbare Zugangsdaten erfolgen.
- API-Schlüssel dürfen nicht im Repository gespeichert werden.

### Verarbeitung vorhandener Bilder

- Eine Funktion darf sich nicht ausschließlich auf neu importierte Medien beschränken.
- Für vorhandene Bilder muss ein kontrollierter Nachbearbeitungs- oder Rebuild-Lauf möglich sein.
- Der Lauf sollte wiederholbar und möglichst idempotent sein.
- Große Bestände sollten in Batches bzw. über Hintergrundjobs verarbeitet werden.
- Fortschritt und Fehler müssen über Logs oder einen nachvollziehbaren Status prüfbar sein.

### Dawarich-Kompatibilität

- Bestehende Dawarich-Funktionen sollen erhalten bleiben.
- Änderungen sollen möglichst klein und upstream-freundlich sein.
- Vorhandene Rails-, Service- und Job-Strukturen sind zu bevorzugen.
- Direkte Änderungen an erzeugten oder extern verwalteten Dateien sind zu vermeiden.

### Docker-Betrieb

- Alle Befehle und Anleitungen müssen die tatsächlichen Compose-Servicenamen verwenden.
- Änderungen an Umgebungsvariablen erfordern in der Regel ein Recreate der betroffenen Container.
- Lokale Dienste wie Photon bleiben ausschließlich im internen Docker-Netz erreichbar, sofern keine andere Anforderung vorliegt.

## Bekannte Themen und Abgrenzungen

### Shared-Link-Fehler

In einer Dawarich-Share-Ansicht wurde beobachtet:

- Bei einigen Tagen werden negative Distanzen angezeigt.
- An denselben Tagen fehlen teilweise Immich-Bilder im Shared-Link.
- In der angemeldeten Ansicht sind die Bilder vorhanden.

Dieser Zusammenhang wurde als separater Dawarich-Fehler behandelt und upstream gemeldet. Er ist nicht automatisch Teil jeder Änderung dieses Repositorys.

### Reverse Geocoding

Photon läuft als lokale Reverse-Geocoding-Instanz und ist aus den Dawarich-Containern erreichbar. Änderungen an der Immich-Bildverarbeitung sollen diese Konfiguration nicht unnötig beeinflussen.

## Qualitätsziele

- Reproduzierbare Installation und Ausführung
- Vollständige Befehle statt fragmentierter Anweisungen
- Kleine, überprüfbare Änderungen
- Nachvollziehbare Logs
- Sichere Behandlung von Zugangsdaten
- Tests für wesentliche Logik
- Dokumentation neuer Konfigurationen und Wartungsbefehle

## Noch zu klärende Punkte

Die folgenden Punkte müssen beim weiteren Ausbau direkt aus dem Code verifiziert und anschließend dokumentiert werden:

- Welche konkrete Tagging- oder Metadatenlogik bereits implementiert ist
- Welche Modelle und Services aktuell verändert wurden
- Wie bestehende Bilder momentan erkannt und verarbeitet werden
- Ob bereits ein Batch-Job, Rake-Task oder Rails-Runner-Skript existiert
- Welche Tests bereits vorhanden sind
- Welche Änderungen gegenüber dem Dawarich-Upstream bestehen
- Welche Branch- und Release-Strategie verwendet wird

Diese Angaben dürfen nicht geraten werden. Ein Agent soll sie durch Analyse des Repositorys ermitteln.

## Definition eines guten nächsten Arbeitsschritts

Ein guter nächster Schritt erfüllt möglichst alle folgenden Kriterien:

1. Er basiert auf einer Analyse des vorhandenen Codes.
2. Er verändert nur die notwendigen Dateien.
3. Er berücksichtigt den vorhandenen Medienbestand.
4. Er ist lokal testbar.
5. Er enthält einen klaren Prüf- oder Rollback-Weg.
6. Er aktualisiert bei Bedarf die Dokumentation unter `AI/`.
