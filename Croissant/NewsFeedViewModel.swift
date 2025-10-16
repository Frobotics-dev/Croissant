//
//  NewsFeedViewModel.swift
//  Dashboard
//
//  Created by Frederik Mondel on 15.10.25.
//

import Foundation
import SwiftUI // For @Published
import Combine // Important for ObservableObject and @Published

// Data structure for a news item
struct NewsItem: Identifiable, Hashable {
    let id = UUID() // Unique ID for ForEach
    let title: String
    let link: URL?
    let description: String? // Can contain more details
    let sourceURL: URL? // Added to identify the source feed
}

// MARK: - Feed Constants
// Must duplicate definition from SettingsView to know the URLs without importing SettingsView
struct RSSFeedConstants {
    static let mixedModeIdentifier = "MIXED_MODE_IDENTIFIER"
    static let mixedModeDisplayName = "All Feeds (Mix)" // Clear display name for the UI filter
    
    static let allFeeds: [String: String] = [
        "ZDF heute": "https://www.zdfheute.de/rss/zdf/nachrichten",
        "Tagesschau Main News": "https://www.tagesschau.de/index~rss2.xml",
        "Tagesschau Technology": "https://www.tagesschau.de/wissen/technologie/index~rss2.xml",
        "BBC Top Stories": "https://feeds.bbci.co.uk/news/rss.xml"
    ]
    
    static var allFeedURLs: [URL] {
        allFeeds.values.compactMap { URL(string: $0) }
    }
    
    static func getSourceDisplayName(for url: URL) -> String? {
        // Searches for the Key (Display Name) based on the Value (URL)
        return RSSFeedConstants.allFeeds.first { $0.value == url.absoluteString }?.key
    }
    
    // Calculates the list of selectable options for the UI (Display Name: URL String)
    static var selectableFeeds: [String: String] {
        var feeds = RSSFeedConstants.allFeeds
        feeds[mixedModeDisplayName] = mixedModeIdentifier
        return feeds
    }
}


class NewsFeedViewModel: NSObject, ObservableObject {
    @Published var newsItems: [NewsItem] = []
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false

    // MARK: - Public Access to Feeds
    
    // Provides the sorted list of feeds for the UI menu: [(DisplayName, URLString)]
    var availableFeedsForMenu: [(key: String, value: String)] {
        // Sort single feeds by name first
        let singleFeeds = RSSFeedConstants.allFeeds.sorted { $0.key < $1.key }
        
        // Create a list, adding Mixed Mode first
        var combinedFeeds: [(key: String, value: String)] = [
            (key: RSSFeedConstants.mixedModeDisplayName, value: RSSFeedConstants.mixedModeIdentifier)
        ]
        
        combinedFeeds.append(contentsOf: singleFeeds)
        return combinedFeeds
    }
    
    // Convenience property to get the display name of the current selection
    var currentFeedDisplayName: String {
        if feedURLString == RSSFeedConstants.mixedModeIdentifier {
            return RSSFeedConstants.mixedModeDisplayName
        }
        
        if let displayName = RSSFeedConstants.allFeeds.first(where: { $0.value == feedURLString })?.key {
            return displayName
        }
        
        // Custom URL or unrecognized URL
        return "Custom Feed"
    }


    // MARK: - RSS Feed URL Management
    // New default value: ZDF heute
    let defaultFeedURLString = RSSFeedConstants.allFeeds["ZDF heute"]!

    @Published var feedURLString: String {
        didSet {
            if feedURLString != RSSFeedConstants.mixedModeIdentifier && !feedURLString.isEmpty {
                UserDefaults.standard.set(feedURLString, forKey: "newsFeedURLString")
            } else if feedURLString == RSSFeedConstants.mixedModeIdentifier {
                 // Save the Mixed Mode Identifier so it's loaded on restart
                 UserDefaults.standard.set(feedURLString, forKey: "newsFeedURLString")
            } else {
                UserDefaults.standard.removeObject(forKey: "newsFeedURLString")
            }
            
            setupFetchDebounce()
        }
    }
    
    // Computed property that returns the current URL as a real URL object (only used in single mode)
    var feedURL: URL? {
        URL(string: feedURLString)
    }

    // Timer for regular updates
    private var refreshTimer: Timer?
    // Debounce timer for URL input
    private var debounceTimer: Timer?
    
    private var cancellables = Set<AnyCancellable>() // For Combine subscriptions
    
    // Using a Task to manage active fetching operations
    private var fetchTask: Task<Void, Never>?

    override init() {
        // Load the saved URL, or use the default URL
        let initialURL = UserDefaults.standard.string(forKey: "newsFeedURLString") ?? defaultFeedURLString
        _feedURLString = Published(initialValue: initialURL)
        
        super.init()
        
        startAutoRefresh()
        
        // Fetch news directly on startup
        DispatchQueue.main.async {
            self.fetchNews()
        }
    }
    
    deinit {
        stopAutoRefresh()
        debounceTimer?.invalidate()
        fetchTask?.cancel()
    }
    
    private func startAutoRefresh() {
        // Reduced frequency for testing/debugging, 900 seconds (15 mins) is good for production
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            self?.fetchNews()
        }
    }
    
    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func setupFetchDebounce() {
        debounceTimer?.invalidate()
        
        // Only load news if the URL is not empty OR Mixed Mode is active
        guard !feedURLString.isEmpty || feedURLString == RSSFeedConstants.mixedModeIdentifier else { return }
        
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.fetchNews()
        }
    }

    // Starts fetching news from the RSS feed(s)
    func fetchNews() {
        // Cancel existing task before starting a new one
        fetchTask?.cancel()
        
        isLoading = true
        errorMessage = nil
        
        if feedURLString == RSSFeedConstants.mixedModeIdentifier {
            fetchTask = Task { await fetchMixedNews() }
        } else {
            fetchTask = Task { await fetchSingleNews() }
        }
    }
    
    // MARK: - Single Feed Fetching (Existing Logic)

    private func fetchSingleNews() async {
        guard let feedURL = self.feedURL else {
            // Do not show an error message if the URL is only empty (in custom mode)
            await MainActor.run {
                if !feedURLString.isEmpty {
                    errorMessage = "Error: Invalid RSS Feed URL."
                } else {
                    errorMessage = nil
                    newsItems = []
                }
                isLoading = false
            }
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: feedURL)
            
            // XMLParser must run on the thread that created it (usually main thread, if we parse synchronously)
            // We run the synchronous parsing on a detached background thread.
            
            let items = try await Task.detached { [weak self] in
                // Use the concurrency-safe parsing function
                return self?.parseRSS(data: data, sourceURL: feedURL) ?? []
            }.value // Wait for the detached task to complete (or cancel)
            
            await MainActor.run { [weak self] in
                self?.newsItems = items
                self?.isLoading = false
                
                if items.isEmpty {
                    // Check if the parsing returned nothing, which might indicate an error or an empty feed
                    self?.errorMessage = "Could not parse any news items from the feed."
                } else {
                    self?.errorMessage = nil
                }
            }
            
        } catch is CancellationError {
            // Task cancelled (e.g., user started typing again)
            await MainActor.run {
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Error loading news: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }

    // MARK: - Mixed Feed Fetching (New Logic)
    
    private func fetchMixedNews() async {
        let allURLs = RSSFeedConstants.allFeedURLs
        
        // Define an array of tasks to fetch all feeds concurrently
        let tasks = allURLs.map { url in
            Task {
                return await self.fetchAndParseFeed(url: url)
            }
        }
        
        // Wait for all tasks to complete
        let results = await withTaskGroup(of: [NewsItem].self, returning: [NewsItem].self) { group in
            for task in tasks {
                group.addTask {
                    do {
                        return try await task.value
                    } catch {
                        // Ignore individual feed errors, continue with others
                        print("Error fetching one feed in mixed mode: \(error.localizedDescription)")
                        return []
                    }
                }
            }
            
            var collectedItems: [NewsItem] = []
            for await items in group {
                collectedItems.append(contentsOf: items)
            }
            return collectedItems
        }
        
        // Process results: Limit to 3 items per unique source URL
        var sourceCounts: [URL: Int] = [:]
        var finalItems: [NewsItem] = []
        
        // Sort items by a reliable date if possible, otherwise rely on the order returned by the parser.
        // Since RSS parsing doesn't include publication date here, we rely on the order returned by the parser (usually newest first).
        
        // Filter and collect: Take the first 3 (newest) entries per source
        for item in results {
            guard let url = item.sourceURL else { continue }
            
            let count = sourceCounts[url, default: 0]
            if count < 3 {
                finalItems.append(item)
                sourceCounts[url] = count + 1
            }
        }

        // Randomly shuffle the final collection
        finalItems.shuffle()
        
        await MainActor.run {
            self.newsItems = finalItems
            self.isLoading = false
            if finalItems.isEmpty {
                 self.errorMessage = "Could not load any news feeds."
            }
        }
    }
    
    // Helper function to fetch data and parse it using concurrency
    private func fetchAndParseFeed(url: URL) async -> [NewsItem] {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // Parsing must be performed in a detached task if it is synchronous and lengthy
            let items = try await Task.detached {
                self.parseRSS(data: data, sourceURL: url)
            }.value
            return items
        } catch is CancellationError {
            return []
        } catch {
            print("Failed to fetch or parse \(url.absoluteString): \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Synchronous XML Parsing Function
    
    // Parses XML data and returns NewsItems. Must be called from a background context.
    private func parseRSS(data: Data, sourceURL: URL) -> [NewsItem] {
        // XMLParserDelegate is stateful. To ensure thread safety in concurrent fetching,
        // we use a fresh, local instance of the delegate structure for each parsing run.
        let parserDelegate = RSSParserDelegate(sourceURL: sourceURL)
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        
        if parser.parse() {
            return parserDelegate.parsedItems
        } else {
            // Handle parsing failure if necessary, but return empty array if failed
            // The delegate will have logged any explicit error.
            return []
        }
    }
}

// MARK: - Thread-Safe XMLParserDelegate Implementation

// Dedicated class for parsing a single RSS feed instance safely in a concurrent environment
class RSSParserDelegate: NSObject, XMLParserDelegate {
    
    private let sourceURL: URL
    var parsedItems: [NewsItem] = []
    
    private var currentElement = ""
    private var currentTitle: String = ""
    private var currentLink: String = ""
    private var currentDescription: String = ""
    
    init(sourceURL: URL) {
        self.sourceURL = sourceURL
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        if elementName == "item" { // Start of a new news article
            currentTitle = ""
            currentLink = ""
            currentDescription = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        switch currentElement {
        case "title":
            currentTitle += string
        case "link":
            currentLink += string
        case "description":
            currentDescription += string
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" { // End of a news article
            let trimmedTitle = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedLink = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDescription = currentDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Requires a valid title to be added
            if !trimmedTitle.isEmpty {
                let newsItem = NewsItem(
                    title: trimmedTitle, 
                    link: URL(string: trimmedLink), 
                    description: trimmedDescription,
                    sourceURL: sourceURL
                )
                parsedItems.append(newsItem)
            }
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        print("XML Parser Error for \(sourceURL.absoluteString): \(parseError.localizedDescription)")
    }
}
