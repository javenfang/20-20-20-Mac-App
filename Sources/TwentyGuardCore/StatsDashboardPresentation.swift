import Foundation

public enum StatsDashboardPage: Int, CaseIterable, Sendable {
    case summary
    case month
}

public enum StatsDashboardSection: Equatable, Sendable {
    case header
    case pageTabs
    case verdict
    case keyMetrics
    case weekTable
    case month
    case quality
}

public enum StatsDashboardAction: Equatable, Sendable {
    case dashboardLoaded
    case pageChanged
    case monthChanged
    case monthDaySelected
}

public enum StatsDashboardRenderScope: Equatable, Sendable {
    case fullPage
    case monthContent
}

public struct StatsDashboardPresentation: Equatable, Sendable {
    public let page: StatsDashboardPage
    public let hasQualityIssues: Bool

    public init(page: StatsDashboardPage, hasQualityIssues: Bool) {
        self.page = page
        self.hasQualityIssues = hasQualityIssues
    }

    public var sections: [StatsDashboardSection] {
        switch page {
        case .summary:
            var sections: [StatsDashboardSection] = [.header, .pageTabs, .verdict, .keyMetrics, .weekTable]
            if hasQualityIssues {
                sections.append(.quality)
            }
            return sections
        case .month:
            return [.header, .pageTabs, .month]
        }
    }

    public static func renderScope(for action: StatsDashboardAction) -> StatsDashboardRenderScope {
        switch action {
        case .monthChanged, .monthDaySelected:
            return .monthContent
        case .dashboardLoaded, .pageChanged:
            return .fullPage
        }
    }
}
