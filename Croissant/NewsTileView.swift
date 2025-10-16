import SwiftUI

struct NewsTileView: View {
    @ObservedObject var viewModel: NewsFeedViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Display the name of the currently selected feed
                Label(viewModel.currentFeedDisplayName, systemImage: "newspaper")
                    .font(.headline)
                
                Spacer()
                
                // MARK: Filter Menu / Icon
                Menu {
                    // Iterate over all available feeds (including Mixed Mode)
                    ForEach(viewModel.availableFeedsForMenu, id: \.value) { displayName, urlString in
                        Button {
                            // Sets the URL, which triggers fetchNews()
                            viewModel.feedURLString = urlString
                        } label: {
                            HStack {
                                Text(displayName)
                                if viewModel.feedURLString == urlString {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle") // Icon for options/filter
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .menuStyle(.borderlessButton) // Ensures the Menu looks good inside the tile
            }

            content
        }
        .onAppear {
            if !viewModel.isLoading && viewModel.newsItems.isEmpty && viewModel.errorMessage == nil {
                viewModel.fetchNews()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView("Loading News...")
                .progressViewStyle(.circular)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .center)
        } else if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .foregroundColor(.red)
                .font(.caption)
        } else if viewModel.newsItems.isEmpty {
            Text("No news found.")
                .foregroundColor(.secondary)
                .font(.subheadline)
        } else {
            // Use ScrollViewReader to enable programmatic scrolling
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        // Use id: \.id as NewsItem is Identifiable, ensuring stable identity even if titles repeat
                        ForEach(viewModel.newsItems.prefix(10), id: \.id) { item in 
                            NewsRowView(item: item) {
                                // Action to perform when a row is expanded
                                // Set animation duration to 0.5s for slower effect
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    proxy.scrollTo(item.id, anchor: .top)
                                }
                            }
                            .id(item.id) // Assign ID for ScrollViewReader
                            .padding(.vertical, 2)
                        }
                    }
                    // Apply animation to the container so movements when expanding/collapsing are animated
                    .animation(.easeInOut(duration: 0.2), value: viewModel.newsItems.count) // Ensure list changes are animated
                }
            }
        }
    }
}

// MARK: - Row View

private struct NewsRowView: View {
    let item: NewsItem
    // Closure to call when expansion happens (used for scrolling)
    let onExpand: () -> Void 
    
    // State to track if the description is expanded (by click)
    @State private var isExpanded: Bool = false

    // Defines the content that should be clickable (to expand/collapse)
    @ViewBuilder
    private var clickableContent: some View {
        // Outer VStack that expands dynamically in height
        VStack(alignment: .leading, spacing: 8) {
            
            // 1. Row Header (Title and Link Button)
            rowContent
                .contentShape(Rectangle())
            
            // 2. The dynamically revealed description
            if isExpanded, let description = item.description, !description.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                }
                .padding(.top, 4) 
                .padding(.horizontal, 12) 
                .padding(.bottom, 4) 
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12) 
    }
    
    var body: some View {
        clickableContent
            // Handle the click gesture to toggle expansion
            .onTapGesture {
                // Only toggle if a description exists
                guard item.description != nil else { return } // KORRIGIERT
                
                // Determine if this click will EXPAND the row
                let shouldExpand = !isExpanded
                
                withAnimation(.easeOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
                
                // Call the scroll action only when expanding
                if shouldExpand {
                    // Call the action passed from the parent ScrollViewReader
                    onExpand()
                }
            }
        // Background and shaping applied to the container
        .background(.thinMaterial)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        // IMPORTANT: Animation on the container so height change is smooth
        // The default animation on the row's height change should remain quick
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        // Ensures the entire area responds to clicks
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            ProviderIconView(systemName: itemProviderSystemName, iconURL: resolvedIconURL)
                .frame(width: 22, height: 22)

            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.primary)
                Spacer()
                
                // Explicit Link Button to open the website
                if let url = item.link {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.circle.fill") // Use a more prominent icon for the link
                            .font(.title3) // Slightly larger icon
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8) // Ensure it's separate from the title
                            .contentShape(Rectangle()) // Makes the area around the icon clickable
                    }
                    .buttonStyle(.plain)
                    // Stops the tap gesture from propagating to the parent onTapGesture
                    .simultaneousGesture(TapGesture().onEnded { })
                }
            }
        }
    }

    // Safely extract optional provider icon hints from item using an optional protocol cast
    private protocol ProviderIconHints {
        var providerIconSystemName: String? { get }
        var providerIconURL: URL? { get }
    }

    private var itemProviderSystemName: String? {
        // NewsItem does not conform to ProviderIconHints, so this will be nil
        (item as? ProviderIconHints)?.providerIconSystemName
    }

    private var itemProviderURL: URL? {
        // NewsItem does not conform to ProviderIconHints, so this will be nil
        (item as? ProviderIconHints)?.providerIconURL
    }

    // Always resolve to the site's favicon derived from the item's link (no domain mapping, no provider hints)
    private var resolvedIconURL: URL? {
        guard let link = item.link, let host = fullHost(from: link) else { return nil }
        return faviconURL(forHost: host)
    }

    // Extracts the full host (keeps subdomains like www)
    private func fullHost(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.host?.lowercased()
    }

    // Attempts multiple common favicon locations; if unknown, falls back to Google S2 service.
    private func faviconURL(forHost host: String) -> URL? {
        // Special-case: zdfheute provides favicon at a stable Next.js static path
        if host.contains("zdfheute.de") {
            return URL(string: "https://www.zdfheute.de/_next/static/media/favicon.73b4cbc4.ico")
        }

        // Variant (a): Try a set of common favicon paths in order of preference
        let candidates = [
            "https://\(host)/favicon.ico",
            "https://\(host)/favicon.png",
            "https://\(host)/favicon-32x32.png",
            "https://\(host)/favicon-16x16.png",
            "https://\(host)/apple-touch-icon.png",
            "https://\(host)/apple-touch-icon-precomposed.png"
        ]

        for candidate in candidates {
            if let url = URL(string: candidate) {
                return url
            }
        }

        // Variant (b): Google S2 favicon service as a robust fallback
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
    }
}

// MARK: - Provider Icon View

private struct ProviderIconView: View {
    let systemName: String?
    let iconURL: URL?

    var body: some View {
        Group {
            if let systemName {
                Image(systemName: systemName)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            } else if let iconURL {
                AsyncImage(url: iconURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .controlSize(.mini)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                fallback
            }
        }
    }

    private var fallback: some View {
        Image(systemName: "globe")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.secondary)
    }
}

// MARK: - Extension for optional binding in ViewBuilders

// The extension .ifLet is no longer strictly necessary since we use ZStack/if let,
// but we leave it in case it is useful elsewhere in the project.
extension View {
    @ViewBuilder
    func ifLet<Content: View, T>(_ value: T?, @ViewBuilder content: (Self, T) -> Content) -> some View {
        if let value = value {
            content(self, value)
        } else {
            self
        }
    }
}
