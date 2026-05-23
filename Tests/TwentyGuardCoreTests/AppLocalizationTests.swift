import XCTest
@testable import TwentyGuardCore

final class AppLocalizationTests: XCTestCase {
    func testAllSupportedLanguagesHaveSameLocalizationKeys() {
        let baseKeys = AppLocalization.localizationKeys(language: AppLocalization.defaultLanguageCode)
        XCTAssertFalse(baseKeys.isEmpty)

        for language in AppLocalization.supportedLanguageCodes {
            XCTAssertEqual(
                AppLocalization.localizationKeys(language: language),
                baseKeys,
                "\(language) Localizable.strings keys must match \(AppLocalization.defaultLanguageCode)"
            )
        }
    }

    func testAllTranslationsKeepFormatSpecifiersCompatible() {
        let baseTable = AppLocalization.localizationTable(language: AppLocalization.defaultLanguageCode)

        for language in AppLocalization.supportedLanguageCodes where language != AppLocalization.defaultLanguageCode {
            let table = AppLocalization.localizationTable(language: language)

            for key in baseTable.keys {
                XCTAssertEqual(
                    formatSpecifiers(in: table[key] ?? ""),
                    formatSpecifiers(in: baseTable[key] ?? ""),
                    "\(language) translation for \(key) must preserve printf format specifiers"
                )
            }
        }
    }

    func testLanguageDetectionUsesSupportedCodes() {
        XCTAssertEqual(AppLocalization.languageCode(for: ["zh-Hans-CN"]), "zh-Hans")
        XCTAssertEqual(AppLocalization.languageCode(for: ["es-US"]), "es")
        XCTAssertEqual(AppLocalization.languageCode(for: ["fr-FR"]), "en")
    }

    func testLocalizedLookupReturnsSelectedLanguage() {
        XCTAssertEqual(AppLocalization.localized("nightRestriction", language: "es"), "Bloqueo Nocturno")
        XCTAssertEqual(AppLocalization.localized("nightRestriction", language: "ja"), "夜間画面ロック")
        XCTAssertEqual(AppLocalization.localized("nightRestriction", language: "ko"), "야간 화면 잠금")
    }

    func testNightOverrideLocalizationsReplaceTestingEscape() {
        let requiredKeys: Set<String> = [
            "nightOverride",
            "nightOverrideRequestTitle",
            "nightOverrideReasonTitle",
            "nightOverrideReasonUrgentWork",
            "nightOverrideReasonLifeTask",
            "nightOverrideReasonFamily",
            "nightOverrideReasonOther",
            "nightOverrideWaiting",
            "nightOverrideWaitExplanation",
            "nightOverrideConfirmPrompt",
            "nightOverrideInputPlaceholder",
            "nightOverrideUnlock",
            "nightOverrideCancel",
            "nightOverrideMismatch",
            "nightOverrideActiveStatus",
            "nightOverrideRecoveryFormat",
            "nightOverrideConfirmationFirst",
            "nightOverrideConfirmationSecond",
            "nightOverrideConfirmationRepeated",
            "statsNightNoOverride",
            "statsNightOverrideFormat"
        ]
        let legacyKeys: Set<String> = [
            "nightTestingExit",
            "nightTestingExitShown",
            "nightTestingExitHidden"
        ]

        for language in AppLocalization.supportedLanguageCodes {
            let keys = AppLocalization.localizationKeys(language: language)
            XCTAssertTrue(requiredKeys.isSubset(of: keys), "\(language) must include all night override keys")
            XCTAssertTrue(keys.isDisjoint(with: legacyKeys), "\(language) must not expose testing escape keys")
        }
    }

    func testTemporaryDisableLocalizationsAreComplete() {
        let requiredKeys: Set<String> = [
            "temporaryDisableOneHour",
            "temporaryDisableActiveStatus",
            "temporaryDisableEndNow",
            "temporaryDisableUnavailableNight"
        ]

        for language in AppLocalization.supportedLanguageCodes {
            let keys = AppLocalization.localizationKeys(language: language)
            XCTAssertTrue(requiredKeys.isSubset(of: keys), "\(language) must include all temporary disable keys")
        }
    }

    func testProtectionStatsLocalizationsAreComplete() {
        let requiredKeys: Set<String> = [
            "statsBreakDisciplineMetric",
            "statsBreakDisciplineDetailFormat",
            "statsExceptionMetric",
            "statsExceptionColumn",
            "statsExceptionNone",
            "statsExceptionCountFormat",
            "statsExceptionDetailFormat",
            "statsNightBoundaryMetric",
            "statsSummaryTab",
            "statsMonthTab",
            "statsMonthSummaryFormat",
            "statsMonthNoSelectedDay",
            "statsSelectedDayDetailFormat",
            "verdictProtectionBypassedTitle",
            "verdictProtectionBypassedReasonFormat"
        ]

        for language in AppLocalization.supportedLanguageCodes {
            let keys = AppLocalization.localizationKeys(language: language)
            XCTAssertTrue(requiredKeys.isSubset(of: keys), "\(language) must include protection statistics keys")
        }
    }

    func testFindsCoreResourceBundleInStandardAppResourcesDirectory() throws {
        let appURL = temporaryDirectory()
            .appendingPathComponent("TwentyGuard.app", isDirectory: true)
        let resourceURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
        let coreBundleURL = resourceURL
            .appendingPathComponent(AppLocalization.coreResourceBundleName, isDirectory: true)

        try FileManager.default.createDirectory(
            at: coreBundleURL,
            withIntermediateDirectories: true
        )

        let resolvedURL = AppLocalization.resolveCoreResourceBundleURL(
            mainBundleURL: appURL,
            mainResourceURL: nil,
            additionalSearchURLs: []
        )

        XCTAssertEqual(resolvedURL?.standardizedFileURL, coreBundleURL.standardizedFileURL)
    }

    func testLocalizationTableLoadsFromPackagedResourceBundleURL() throws {
        let coreBundleURL = temporaryDirectory()
            .appendingPathComponent(AppLocalization.coreResourceBundleName, isDirectory: true)
        let englishURL = coreBundleURL.appendingPathComponent("en.lproj", isDirectory: true)

        try FileManager.default.createDirectory(
            at: englishURL,
            withIntermediateDirectories: true
        )
        try #"""
        "fixtureKey" = "Fixture Value";
        """#.write(
            to: englishURL.appendingPathComponent("Localizable.strings"),
            atomically: true,
            encoding: .utf8
        )

        let table = AppLocalization.localizationTable(
            language: "en",
            resourceBundleURL: coreBundleURL
        )

        XCTAssertEqual(table["fixtureKey"], "Fixture Value")
    }

    private func formatSpecifiers(in value: String) -> [String] {
        let pattern = "%(?:\\d+\\$)?(?:[0-9.]+)?[@d]"
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(value.startIndex..<value.endIndex, in: value)

        return regex.matches(in: value, range: range).map {
            String(value[Range($0.range, in: value)!])
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
