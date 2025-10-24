import SwiftUI
import CoreLocation

// MARK: - Hauptansicht
struct TransitTileView: View {
    // Dependencies required by ContentView
    @ObservedObject var viewModel: TransitViewModel
    @ObservedObject var locationManager: LocationManager
    
    // NEU: AppStorage, um den Debug-Status zu lesen
    @AppStorage("isDebuggingEnabled") private var isDebuggingEnabled: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            
            // Titel und Aktualisierungsstatus (aus TransitTileView 2)
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "tram.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Transit")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()

                // Dropdown zur Auswahl umliegender Haltestellen (wie im NewsFeed)
                if !viewModel.nearbyStops.isEmpty {
                    Menu {
                        // Liste aller geladenen Haltestellen anzeigen
                        ForEach(viewModel.nearbyStops, id: \.self) { stop in
                            Button(action: {
                                // Auswahl setzen und Abfahrten aktualisieren
                                viewModel.selectedStop = stop
                                Task {
                                    await viewModel.fetchDepartures(for: stop, storeUnder: stop.id)
                                }
                            }) {
                                HStack {
                                    Text(stop.name)
                                    if stop.id == viewModel.selectedStop?.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                            .foregroundColor(.secondary)
                            .accessibilityLabel("Select stop")
                    }
                    .buttonStyle(.plain)
                    .menuStyle(.borderlessButton)
                }
                
                if viewModel.isLoading && viewModel.departuresByStop.isEmpty {
                    ProgressView()
                } else if let error = viewModel.errorMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .help(error)
                }
            }
            
            // Anzeige des ausgewählten oder ersten Halts
            if let selectedStop = viewModel.selectedStop {
                HStack(alignment: .firstTextBaseline) {
                    Text(selectedStop.name)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    // Zeige den Zeitstempel nur an, wenn der Debug-Modus aktiviert ist
                    if isDebuggingEnabled {
                        Text(viewModel.updatedLabel)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
            } else if locationManager.isLoading {
                Text("Fetching location…")
                    .foregroundColor(.secondary)
            } else if !viewModel.isLoading && viewModel.nearbyStops.isEmpty {
                Text("No nearby stop found.")
                    .foregroundColor(.secondary)
            }
            
            Divider()

            // Liste der Abfahrten
            if viewModel.isLoading && viewModel.departures.isEmpty {
                Spacer()
                ProgressView("Loading departures…")
                Spacer()
            } else if viewModel.departures.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("No current departures.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.departures) { departure in
                            DepartureRow(departure: departure)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Zeile für eine Abfahrt
private struct DepartureRow: View {
    let departure: Departure
    
    // Hilfsfunktion zur Darstellung der Minuten
    private func minutesText(minutes: Int, isDelayed: Bool) -> Text {
        if minutes < 1 {
            return Text("NOW")
                .foregroundColor(.red)
                .fontWeight(.bold)
        } else if isDelayed {
            return Text("\(minutes) min")
                .foregroundColor(.red)
                .fontWeight(.medium)
                .monospacedDigit()
        } else {
            return Text("\(minutes) min")
                .foregroundColor(.primary)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            
            // 1. Icon und Linie
            HStack(spacing: 5) {
                Image(systemName: departure.line.systemIconName)
                    .font(.title3)
                    .frame(width: 25)
                    .foregroundStyle(Color.accentColor)
                
                Text(departure.line.name)
                    .font(.headline)
                    .fontWeight(.bold)
                    .frame(width: 40, alignment: .leading)
            }
            .frame(width: 70, alignment: .leading) // Feste Breite für Icon/Linie

            // 2. Richtung / Ziel
            VStack(alignment: .leading) {
                if let direction = departure.direction {
                    Text("→ \(direction)")
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                }
                
                // 3. Minuten bis zur Abfahrt (darunter)
                if let planned = departure.plannedMinutesUntilDeparture {
                    if planned <= 1 {
                        // Wenn die geplante Abfahrt jetzt wäre, aber Verspätung besteht: nur den Offset zeigen (rot)
                        if !departure.delayOffsetLabel.isEmpty {
                            Text(departure.delayOffsetLabel)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.red)
                                .monospacedDigit()
                        } else if let eta = departure.minutesUntilDeparture, eta <= 1 {
                            // Tatsächliche Abfahrt ist jetzt: "NOW" anzeigen
                            minutesText(minutes: eta, isDelayed: false)
                                .font(.caption)
                        } else {
                            // Fallback: geplante Minuten (0/1) anzeigen
                            Text("\(planned) min")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .monospacedDigit()
                        }
                    } else {
                        HStack(spacing: 4) {
                            // Ursprüngliche Restzeit (weiß/primary)
                            Text("\(planned) min")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .monospacedDigit()
                            // Verspätungs-Offset (z. B. +3) in Rot, nur wenn vorhanden/≠0
                            if !departure.delayOffsetLabel.isEmpty {
                                Text(departure.delayOffsetLabel)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.red)
                                    .monospacedDigit()
                            }
                        }
                    }
                } else if let minutes = departure.minutesUntilDeparture {
                    // Fallback: zeige aktuelle ETA wie bisher
                    minutesText(minutes: minutes, isDelayed: departure.isDelayed)
                        .font(.caption)
                }
            }
            
            Spacer()
            
            // 4. Zeitdarstellung (Rechtsbündig)
            VStack(alignment: .trailing) {
                if departure.isDelayed {
                    HStack(spacing: 4) {
                        Text(departure.plannedTimeString)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .strikethrough(true, color: .secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                        Text(departure.actualTimeString)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                } else {
                    // Normale Abfahrtszeit
                    Text(departure.timeString)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .monospacedDigit()
                }
            }
            .frame(width: 100, alignment: .trailing)
        }
    }
}
