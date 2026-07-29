# KI-Projektdokumentation

## Zweck

Der Ordner `AI/` enthält das dauerhafte Projektwissen für KI-gestützte Entwicklungswerkzeuge und menschliche Entwickler.

Er soll verhindern, dass Architektur, Ziele, Entscheidungen und bekannte Probleme bei jeder neuen Unterhaltung erneut erklärt werden müssen.

## Einstieg

Für einen neuen Agenten oder Entwickler gilt folgende Reihenfolge:

1. `../AGENTS.md`
2. `PROJECT.md`
3. später ergänzte Architektur- und Entwicklungsdokumente

## Aktueller Stand

In Schritt 1 wurden angelegt:

```text
AGENTS.md
AI/README.md
AI/PROJECT.md
```

Weitere geplante Dokumente:

```text
AI/ARCHITECTURE.md
AI/DEVELOPMENT.md
AI/IMMICH.md
AI/DAWARICH.md
AI/BUGS.md
AI/ROADMAP.md
AI/DECISIONS.md
AI/TESTING.md
AI/prompts/
```

## Pflegeprinzipien

- Die Dokumentation beschreibt den tatsächlichen Stand des Repositorys.
- Vermutungen werden als Vermutungen gekennzeichnet.
- Veraltete Informationen werden korrigiert, nicht nur ergänzt.
- Technische Entscheidungen erhalten eine kurze Begründung.
- Zugangsdaten und private Schlüssel gehören nicht in diese Dateien.
- Befehle sollen vollständig und direkt ausführbar sein.

## Verwendung in VS Code

Viele KI-Erweiterungen berücksichtigen eine `AGENTS.md` im Projektstamm automatisch oder können angewiesen werden, sie zuerst zu lesen.

Ein geeigneter Startauftrag im VS-Code-Chat lautet:

```text
Lies zuerst AGENTS.md sowie AI/README.md und AI/PROJECT.md. Fasse danach dein Verständnis des Projekts zusammen, bevor du Änderungen vornimmst.
```

Für spätere Aufgaben genügt häufig ein kurzer Auftrag wie:

```text
Beachte die Projektregeln aus AGENTS.md. Untersuche, warum bestehende Immich-Bilder nicht nachbearbeitet werden, und schlage eine kleine, testbare Änderung vor.
```
