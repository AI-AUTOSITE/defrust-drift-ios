@testable import Drift
import Foundation
import Testing

@MainActor
@Suite("CancellationGuideStore")
struct CancellationGuideStoreTests {

    // MARK: - Fixtures

    private func makeGuide(
        id: String,
        name: String,
        category: String,
        regions: [String],
        score: Int,
        verified: String
    ) -> CancellationGuide {
        CancellationGuide(
            id: id,
            serviceName: name,
            category: category,
            regionAvailability: regions,
            primaryCancelURL: nil,
            appleBilledOption: true,
            steps: [CancellationStep(order: 1, action: "Open settings", supportingNote: nil)],
            estimatedTimeMinutes: 1,
            lastVerifiedDate: verified,
            darkPatternScore: score,
            warningNote: nil,
            notes: nil
        )
    }

    private func fixtures() -> [CancellationGuide] {
        [
            makeGuide(id: "netflix", name: "Netflix", category: "Streaming",
                      regions: ["US", "UK"], score: 2, verified: "2026-05-27"),
            makeGuide(id: "hulu", name: "Hulu", category: "Streaming",
                      regions: ["US"], score: 5, verified: "2026-05-27"),
            makeGuide(id: "siriusxm", name: "SiriusXM", category: "Music",
                      regions: ["US"], score: 9, verified: "2020-01-01"),
            makeGuide(id: "spotify", name: "Spotify", category: "Music",
                      regions: ["US", "UK", "CA", "AU"], score: 3, verified: "2026-05-27")
        ]
    }

    private func makeDate(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)!
    }

    // MARK: - Decoding

    @Test("Decodes guides from JSON, including null optionals")
    func decodesJSON() throws {
        let json = """
        [
          {"id":"netflix","serviceName":"Netflix","category":"Streaming",
           "regionAvailability":["US","UK"],"primaryCancelURL":"https://x.test",
           "appleBilledOption":false,
           "steps":[{"order":1,"action":"Open","supportingNote":"note"},
                    {"order":2,"action":"Confirm","supportingNote":null}],
           "estimatedTimeMinutes":3,"lastVerifiedDate":"2026-05-27",
           "darkPatternScore":2,"warningNote":null,"notes":"kept"},
          {"id":"apple-tv-plus","serviceName":"Apple TV+","category":"Streaming",
           "regionAvailability":["US"],"primaryCancelURL":null,
           "appleBilledOption":true,
           "steps":[{"order":1,"action":"Settings","supportingNote":null}],
           "estimatedTimeMinutes":2,"lastVerifiedDate":"2026-05-27",
           "darkPatternScore":1,"warningNote":null,"notes":null}
        ]
        """
        let guides = try JSONDecoder().decode([CancellationGuide].self, from: Data(json.utf8))
        #expect(guides.count == 2)

        let netflix = try #require(guides.first { $0.id == "netflix" })
        #expect(netflix.primaryCancelURL == "https://x.test")
        #expect(netflix.appleBilledOption == false)
        #expect(netflix.steps.count == 2)
        #expect(netflix.steps[1].supportingNote == nil)
        #expect(netflix.notes == "kept")

        let appleTV = try #require(guides.first { $0.id == "apple-tv-plus" })
        #expect(appleTV.primaryCancelURL == nil)   // Apple-billed
        #expect(appleTV.appleBilledOption == true)
    }

    // MARK: - Query API

    @Test("guide(for:) finds by serviceID and returns nil for unknown")
    func guideLookup() {
        let store = CancellationGuideStore(guides: fixtures())
        #expect(store.guide(for: "netflix")?.serviceName == "Netflix")
        #expect(store.guide(for: "nonexistent") == nil)
    }

    @Test("Region filter keeps only guides available in userRegion")
    func regionFilter() {
        let store = CancellationGuideStore(guides: fixtures())
        store.userRegion = "UK"
        let ids = Set(store.regionFilteredGuides.map(\.id))
        #expect(ids == ["netflix", "spotify"])   // hulu & siriusxm are US-only
    }

    @Test("Search filters by service name, case-insensitive")
    func search() {
        let store = CancellationGuideStore(guides: fixtures())
        store.searchQuery = "SPOT"
        #expect(store.filteredAndSortedGuides.map(\.id) == ["spotify"])
    }

    @Test("Category filter narrows to one category")
    func categoryFilter() {
        let store = CancellationGuideStore(guides: fixtures())
        store.selectedCategory = "Music"
        let ids = Set(store.filteredAndSortedGuides.map(\.id))
        #expect(ids == ["siriusxm", "spotify"])
    }

    @Test("Dark-pattern sort orders the worst offender first")
    func worstOffendersSort() {
        let store = CancellationGuideStore(guides: fixtures())
        store.sortMode = .darkPatternDescending
        #expect(store.filteredAndSortedGuides.first?.id == "siriusxm")   // score 9
    }

    @Test("Grouping by category sorts categories and names")
    func grouping() {
        let store = CancellationGuideStore(guides: fixtures())
        let grouped = store.guidesGroupedByCategory
        #expect(grouped.map(\.category) == ["Music", "Streaming"])
        #expect(grouped.first?.guides.map(\.id) == ["siriusxm", "spotify"])
    }

    // MARK: - Staleness

    @Test("isStale flags guides verified more than 90 days ago")
    func staleness() throws {
        let store = CancellationGuideStore(guides: fixtures())
        let now = makeDate("2026-06-15")
        let netflix = try #require(store.guide(for: "netflix"))    // 2026-05-27 → ~19 days
        let sirius = try #require(store.guide(for: "siriusxm"))    // 2020-01-01 → years
        #expect(store.isStale(netflix, asOf: now) == false)
        #expect(store.isStale(sirius, asOf: now) == true)
    }

    @Test("isStale treats an unparseable date as stale")
    func malformedDateIsStale() {
        let bad = makeGuide(id: "x", name: "X", category: "C",
                            regions: ["US"], score: 1, verified: "not-a-date")
        let store = CancellationGuideStore(guides: [bad])
        #expect(store.isStale(bad) == true)
    }
}
