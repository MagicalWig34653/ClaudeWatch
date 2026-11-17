import XCTest
import SwiftData
@testable import ClaudeWatch
import ClaudeWatchCore

/// Query result growth, not a measurement of SwiftUI's private Observation registrars.
@MainActor
final class MemoryQueryTests: XCTestCase {
    func testHistoricalSessionGrowthDoesNotGrowMenuOrOverviewResults() throws {
        let container = DataStore.makeInMemory()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for index in 0..<400 {
            let session = ClaudeSession(id: "old-\(index)", projectName: "Old", source: .local,
                                        status: .finished, startedAt: now.addingTimeInterval(-86_400 * 2))
            context.insert(session)
        }
        for index in 0..<8 {
            let session = ClaudeSession(id: "active-\(index)", projectName: "Active", source: .local,
                                        status: index < 6 ? .needsInput : .running, startedAt: now)
            context.insert(session)
        }
        try context.save()

        XCTAssertEqual(try context.fetch(SessionQueries.menuAttention).count, 5)
        XCTAssertEqual(try context.fetch(SessionQueries.menuRunning).count, 2)
        XCTAssertEqual(try context.fetch(SessionQueries.menuFinished).count, 3)
        XCTAssertEqual(try context.fetch(SessionQueries.overviewAttention).count, 6)
        XCTAssertEqual(try context.fetch(SessionQueries.overviewRecent).count, 5)
        XCTAssertEqual(try context.fetch(SessionQueries.finishedToday(now: now)).count, 0)
        XCTAssertEqual(try context.fetch(SessionQueries.list(filter: .active, search: "")).count, 8)
        XCTAssertEqual(try context.fetch(SessionQueries.list(filter: .all, search: " old ")).count, 400)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ClaudeSession>()), 408)
    }

    func testEventPagesStayBoundedAsHistoryGrowsAndPreserveAllRecords() throws {
        let container = DataStore.makeInMemory()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let event = ClaudeEvent(type: .finished, sessionID: "s1", timestamp: now)
        let count = EventHistoryQuery.pageSize * 3 + 7
        for index in 0..<count {
            context.insert(ClaudeEventRecord(event: event, fingerprint: "\(index)", isDuplicate: false,
                                            receivedAt: now.addingTimeInterval(Double(index))))
            // Repeatedly query the same production descriptor while history grows.
            if index % EventHistoryQuery.pageSize == 0 {
                try context.save()
                XCTAssertLessThanOrEqual(try context.fetch(EventHistoryQuery.page(sessionID: "s1", index: 0)).count,
                                         EventHistoryQuery.pageSize)
            }
        }
        context.insert(ClaudeEventRecord(event: ClaudeEvent(type: .finished, sessionID: "other", timestamp: now),
                                        fingerprint: "other", isDuplicate: false, receivedAt: now))
        try context.save()

        var ids = Set<UUID>()
        var dates: [Date] = []
        for page in 0..<4 {
            let records = try context.fetch(EventHistoryQuery.page(sessionID: "s1", index: page))
            XCTAssertLessThanOrEqual(records.count, EventHistoryQuery.pageSize)
            ids.formUnion(records.map(\.id))
            dates.append(contentsOf: records.map(\.receivedAt))
        }
        XCTAssertEqual(ids.count, count, "All older events remain reachable, with no overlaps or gaps")
        XCTAssertEqual(dates, dates.sorted(by: >))
        XCTAssertTrue(try context.fetch(EventHistoryQuery.page(sessionID: "s1", index: 4)).isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ClaudeEventRecord>()), count + 1)
    }

    func testQueriesFollowStatusChangesSearchAndFinishedDateFallback() throws {
        let container = DataStore.makeInMemory()
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let session = ClaudeSession(id: "s1", projectName: "Backend", source: .local,
                                    status: .needsInput, startedAt: now)
        session.lastMessage = "Choose DATABASE"
        context.insert(session)
        try context.save()
        XCTAssertEqual(try context.fetch(SessionQueries.list(filter: .attention, search: " database ")).count, 1)
        session.status = .failed
        try context.save()
        XCTAssertTrue(try context.fetch(SessionQueries.menuAttention).isEmpty)
        XCTAssertEqual(try context.fetch(SessionQueries.list(filter: .finished, search: "backend")).count, 1)
        XCTAssertTrue(try context.fetch(SessionQueries.menuFinished).isEmpty, "The menu only shows successful finishes")
        session.status = .finished
        try context.save()
        XCTAssertEqual(try context.fetch(SessionQueries.finishedToday(now: now)).count, 1)
        session.finishedAt = now.addingTimeInterval(-86_400 * 2)
        try context.save()
        XCTAssertTrue(try context.fetch(SessionQueries.finishedToday(now: now)).isEmpty)
    }
}
