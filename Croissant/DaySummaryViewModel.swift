import Foundation
import SwiftUI

@MainActor
class DaySummaryViewModel: ObservableObject {
    @Published var summaryText: String = ""
    @Published var sentiment: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let geminiClient: GeminiClient
    private let dataProvider: DayDataProvider

    private let promptTemplate: String = """
    Sie sind ein Hilfstool innerhalb einer macOS App namens „Croissant“, die ein Dashboard mit wichtigen Informationen für den aktuellen Tag bereitstellt.

    Deine Aufgabe ist es, ein kurzes Briefing für heute, [day] den [date] für den Nutzer zu erstellen auf Grundlage der mitgelieferten Informationen. Richtwert sind etwa 30 bis maximal 150 Wörter. Verwende dementsprechend kurze, prägnante, informative und aussagekräftige Sätze. Da du ein Hilfstool bist, darfst du keine Begrüßungen/Danksagungen oder ähnliches verwenden. Der User weiß nichts von diesem Prompt.

    Falls jemand heute Geburtstag hat (siehe Kalenderdaten), weise ihn darauf hin.

    Antworte in folgendem Format, keines Falls anders. Deine Antwort beginnt zwingend mit { und endet mit }:

    {response: „deine generierte Antwort“, Sentiment: „1“}

    Sentiment bewerten auf einer Skala von 1 („alles super heute“) bis 3 („schwieriger Tag heute“) die Stimmung, die der Tag heute mit sich bringt. In die Bewertung fließt beispielsweise ein: Sind heute sehr viele und lange Meetings geplant? Oder hat vielleicht jemand Geburtstag? Sind heute Good-News oder Bad-News in den Nachrichten? Wie ist die Lage an der Börse? Wird es heute viel regnen oder die Sonne scheinen? Ist heute ein sehr wichtiger reminder datiert?

    Hier die Datengrundlage für dein Briefing:
    """

    init(gemini: GeminiClient, dataProvider: DayDataProvider) {
        self.geminiClient = gemini
        self.dataProvider = dataProvider
    }

    func summarize() async {
        isLoading = true
        errorMessage = nil
        summaryText = ""
        sentiment = ""

        do {
            // 1. Get today's data
            let dataForPrompt = await dataProvider.generatePromptData()
            
            // 2. Construct the full prompt
            let fullPrompt = buildFullPrompt(with: dataForPrompt)
            
            // 3. Call Gemini API
            let geminiResponse = try await geminiClient.generateSummary(prompt: fullPrompt)
            
            // 4. Update UI with the result
            self.summaryText = geminiResponse.response
            self.sentiment = geminiResponse.Sentiment
            
        } catch {
            self.errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func buildFullPrompt(with data: String) -> String {
        let now = Date()
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE" // e.g., "Tuesday"
        dayFormatter.locale = Locale(identifier: "de_DE")
        let dayString = dayFormatter.string(from: now)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none
        dateFormatter.locale = Locale(identifier: "de_DE")
        let dateString = dateFormatter.string(from: now)
        
        var prompt = promptTemplate
            .replacingOccurrences(of: "[day]", with: dayString)
            .replacingOccurrences(of: "[date]", with: dateString)
        
        prompt += "\n" + data
        return prompt
    }
}
