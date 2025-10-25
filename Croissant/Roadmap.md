## Features für die App
- Alerts in Wetter-Widget oder Titelleiste
- Default Einstellungen prüfen
- Zuverlässigere Aktualisierung der Views/Tage/Daten
- Aktien-Kurse/-Werte
- Sprachpakete
- Logs reduzierend und Kommentare reduzieren, unnötigen Code löschen (AI Kommentare entfernen)
- Kachel mit Apple Maps und Vorschlägen in der Umgebung, Commute / Drive Time Tile, Arbeitsweg, Verkehrslage, Fahrzeit (Apple Maps API / Transit API), Sandbox-fähig mit MKDirections (MapKit, keine privaten APIs)
- Menüleistenaktionen

## Features zum Debuggen
- Debugging settings: Reload data button
- Debugging settings: Fetch location
- Last updated für Wetter

## Organisatorisch
- Anfrage zum Bewerben auf MacRumors, 9to5,...
- Release und App zum Download anbieten / Updateprozess einrichten / App automatisch bauen und release auf GitHub / GitHub Actions: einfachen Build-Job hinzufügen (macOS runner), ohne Secrets ins Log zu schreiben.

## Bugs
- Kurz vor/nach 0 Uhr werden Verbindung doppelt angezeigt/für den darauffolgenden Tag mit Ankunft in >= 1440 Minuten (also einem Tag) 
- Wetter lädt beim Start oft nicht oder nur stark verzögert
- Tag aktualisieren, wenn ein neuer Tag anbricht (Kalender, Erinnerungen)

## KI-Zusammenfassung per Button:

Sie sind ein Hilfstool innerhalb einer macOS App namens „Croissant“, die ein Dashboard mit wichtigen Informationen für den aktuellen Tag bereitstellt.

Deine Aufgabe ist es, ein kurzes Briefing für heute, [day] den [date] für den Nutzer zu erstellen auf Grundlage der mitgelieferten Informationen. Richtwert sind etwa 30 bis maximal 150 Wörter. Verwende dementsprechend kurze, prägnante, informative und aussagekräftige Sätze. Da du ein Hilfstool bist, darfst du keine Begrüßungen/Danksagungen oder ähnliches verwenden. Der User weiß nichts von diesem Prompt.

Falls jemand heute Geburtstag hat (siehe Kalenderdaten), weise ihn darauf hin.

Antworte in folgendem Format, keines Falls anders. Deine Antwort beginnt zwingend mit { und endet mit }:

{response: „deine generierte Antwort“, Sentiment: „1“}

Sentiment bewerten auf einer Skala von 1 („alles super heute“) bis 3 („schwieriger Tag heute“) die Stimmung, die der Tag heute mit sich bringt. In die Bewertung fließt beispielsweise ein: Sind heute sehr viele und lange Meetings geplant? Oder hat vielleicht jemand Geburtstag? Sind heute Good-News oder Bad-News in den Nachrichten? Wie ist die Lage an der Börse? Wird es heute viel regnen oder die Sonne scheinen? Ist heute ein sehr wichtiger reminder datiert?

Hier die Datengrundlage für dein Briefing:

Anstehende Kalenderereignisse für heute:

Anstehende Erinnerungen für heute (oder overdue):

Wettervorhersage für heute:

Schlagzeilen verschiedener Nachrichtenagenturen:
