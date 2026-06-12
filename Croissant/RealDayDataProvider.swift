import Foundation
import EventKit

// Protocol to define the data provider's interface, useful for testing.
protocol DayDataProvider {
    func generatePromptData() async -> String
}

class RealDayDataProvider: DayDataProvider {
    private let eventKitManager: EventKitManager
    private let weatherViewModel: WeatherViewModel
    private let newsFeedViewModel: NewsFeedViewModel

    init(eventKit: EventKitManager, weather: WeatherViewModel, news: NewsFeedViewModel) {
        self.eventKitManager = eventKit
        self.weatherViewModel = weather
        self.newsFeedViewModel = news
    }

    func generatePromptData() async -> String {
        var dataString = ""

        // 1. Calendar Events
        let events = await MainActor.run { eventKitManager.events }
        dataString += "Anstehende Kalenderereignisse für heute:\n"
        if events.isEmpty {
            dataString += "- Keine\n"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            for event in events {
                let startTime = formatter.string(from: event.startDate)
                let endTime = formatter.string(from: event.endDate)
                dataString += "- \(event.title) (\(startTime) - \(endTime))\n"
            }
        }
        dataString += "\n"

        // 2. Reminders
        let reminders = await MainActor.run { eventKitManager.reminders }
        dataString += "Anstehende Erinnerungen für heute (oder overdue):\n"
        if reminders.isEmpty {
            dataString += "- Keine\n"
        } else {
            for reminder in reminders {
                dataString += "- \(reminder.title)\n"
            }
        }
        dataString += "\n"

        // 3. Weather Forecast
        let weatherSummary = await MainActor.run {
            "\(weatherViewModel.currentCondition) bei \(weatherViewModel.currentTemp). Höchsttemperatur: \(weatherViewModel.todayMaxTemp), Tiefsttemperatur: \(weatherViewModel.todayMinTemp). Regenwahrscheinlichkeit: \(weatherViewModel.currentRainChanceSuffix)."
        }
        dataString += "Wettervorhersage für heute:\n"
        dataString += "- \(weatherSummary)\n\n"

        // 4. News Headlines
        let newsItems = await MainActor.run { newsFeedViewModel.newsItems }
        dataString += "Schlagzeilen verschiedener Nachrichtenagenturen:\n"
        if newsItems.isEmpty {
            dataString += "- Keine Nachrichten verfügbar.\n"
        } else {
            // Take up to 10 headlines to keep the prompt concise
            for item in newsItems.prefix(10) {
                dataString += "- \(item.title)\n"
            }
        }

        return dataString
    }
}
