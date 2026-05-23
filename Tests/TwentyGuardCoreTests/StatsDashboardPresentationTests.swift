import XCTest
@testable import TwentyGuardCore

final class StatsDashboardPresentationTests: XCTestCase {
    func testDefaultSummaryPageDoesNotIncludeMonthSection() {
        let presentation = StatsDashboardPresentation(page: .summary, hasQualityIssues: true)

        XCTAssertEqual(
            presentation.sections,
            [.header, .pageTabs, .verdict, .keyMetrics, .weekTable, .quality]
        )
        XCTAssertFalse(presentation.sections.contains(.month))
    }

    func testMonthPageContainsOnlySharedChromeAndMonthSection() {
        let presentation = StatsDashboardPresentation(page: .month, hasQualityIssues: true)

        XCTAssertEqual(presentation.sections, [.header, .pageTabs, .month])
    }

    func testMonthInteractionsRefreshOnlyMonthContent() {
        XCTAssertEqual(
            StatsDashboardPresentation.renderScope(for: .monthChanged),
            .monthContent
        )
        XCTAssertEqual(
            StatsDashboardPresentation.renderScope(for: .monthDaySelected),
            .monthContent
        )
    }
}
