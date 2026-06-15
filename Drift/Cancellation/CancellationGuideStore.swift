import Foundation
import Observation
import StoreKit

/// Errors specific to cancellation guide loading.
enum CancellationGuideError: LocalizedError {
    case missingFile
    case decodingFailed(underlying: Error)
    case unknownService(id: String)

    var errorDescription: String? {
        switch self {
        case .missingFile:
            return "cancellation_guides_v1.json was not found in the app bundle."
        case .decodingFailed(let underlying):
            return "Failed to decode cancellation guides: \(underlying.localizedDescription)"
        case .unknownService(let id):
            return "No cancellation guide is bundled for service id \"\(id)\"."
        }
    }
}

/// Loads the bundled cancellation guides and serves region / category / search / sort and
/// staleness queries over them. Local-first: no network. `@Observable` to match `DriftStore`.
@Observable
final class CancellationGuideStore {

    // MARK: - Public state
    private(set) var allGuides: [CancellationGuide] = []
    private(set) var loadError: CancellationGuideError?

    // User-facing filters / state
    var searchQuery: String = ""
    var selectedCategory: String?               // nil = all
    var userRegion: String = "US"               // bound to the current App Store storefront
    var sortMode: SortMode = .alphabetical

    enum SortMode {
        case alphabetical
        case darkPatternDescending   // "worst offenders" view
    }

    // MARK: - Init
    init(bundle: Bundle = .main, filename: String = "cancellation_guides_v1") {
        load(from: bundle, filename: filename)
    }

    /// Test / preview seam: build a store from in-memory guides, skipping bundle loading.
    init(guides: [CancellationGuide]) {
        self.allGuides = guides
    }

    // MARK: - Loading
    private func load(from bundle: Bundle, filename: String) {
        guard let url = bundle.url(forResource: filename, withExtension: "json") else {
            self.loadError = .missingFile
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            // Dates are plain strings (yyyy-MM-dd); decoded as String, parsed lazily.
            let decoded = try decoder.decode([CancellationGuide].self, from: data)
            self.allGuides = decoded
        } catch let error as DecodingError {
            self.loadError = .decodingFailed(underlying: error)
            #if DEBUG
            print("[CancellationGuideStore] DecodingError: \(error)")
            #endif
        } catch {
            self.loadError = .decodingFailed(underlying: error)
        }
    }

    // MARK: - Query API

    /// Guides visible to the user's region.
    var regionFilteredGuides: [CancellationGuide] {
        allGuides.filter { $0.regionAvailability.contains(userRegion) }
    }

    /// Region filter + category + search + sort.
    var filteredAndSortedGuides: [CancellationGuide] {
        var result = regionFilteredGuides

        if let category = selectedCategory, !category.isEmpty {
            result = result.filter { $0.category == category }
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { $0.serviceName.localizedCaseInsensitiveContains(query) }
        }

        switch sortMode {
        case .alphabetical:
            result.sort { $0.serviceName.localizedCaseInsensitiveCompare($1.serviceName) == .orderedAscending }
        case .darkPatternDescending:
            result.sort {
                if $0.darkPatternScore == $1.darkPatternScore {
                    return $0.serviceName < $1.serviceName
                }
                return $0.darkPatternScore > $1.darkPatternScore
            }
        }
        return result
    }

    /// Region-filtered guides grouped by category (for sectioned lists).
    var guidesGroupedByCategory: [(category: String, guides: [CancellationGuide])] {
        let grouped = Dictionary(grouping: regionFilteredGuides, by: \.category)
        return grouped
            .sorted { $0.key < $1.key }
            .map { (category: $0.key, guides: $0.value.sorted { $0.serviceName < $1.serviceName }) }
    }

    /// Look up a guide by serviceID (used by Subscription rows).
    func guide(for serviceID: String) -> CancellationGuide? {
        allGuides.first { $0.id == serviceID }
    }

    // MARK: - Staleness

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Returns true when the guide was verified more than `days` ago (default 90),
    /// or when its date cannot be parsed (treated as stale to prompt re-verification).
    func isStale(_ guide: CancellationGuide, asOf now: Date = Date(), days: Int = 90) -> Bool {
        guard let verified = Self.dateFormatter.date(from: guide.lastVerifiedDate) else {
            return true
        }
        let threshold = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        return verified < threshold
    }
}

// MARK: - Region (App Store storefront)

extension CancellationGuideStore {
    /// Map the current App Store storefront (ISO 3166-1 alpha-3) to Drift's region codes.
    @MainActor
    func refreshUserRegion() async {
        if let storefront = await Storefront.current {
            switch storefront.countryCode {
            case "USA": userRegion = "US"
            case "GBR": userRegion = "UK"
            case "CAN": userRegion = "CA"
            case "AUS": userRegion = "AU"
            default: userRegion = "US"   // fallback
            }
        }
    }
}
