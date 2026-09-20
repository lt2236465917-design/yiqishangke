// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KegeParserRegression",
    platforms: [
        .macOS(.v13),
        .iOS(.v17)
    ],
    products: [
        .library(name: "KegeParser", targets: ["KegeParser"])
    ],
    targets: [
        .target(
            name: "KegeParser",
            path: ".",
            sources: [
                "Shared/ChinaWeekday.swift",
                "Shared/ClassSession.swift",
                "Kege/Parser/TimetableHeuristics.swift",
                "Kege/Parser/ZgysyjyMeeting.swift",
                "Kege/Parser/WeeklyGridOCRParser.swift",
                "Kege/Parser/ZgysyjyParser.swift",
                "Kege/Parser/SchoolParser.swift"
            ]
        ),
        .testTarget(
            name: "KegeParserTests",
            dependencies: ["KegeParser"],
            path: "ParserRegression",
            exclude: [
                "generate_fixtures.py",
                "run_offline.py",
                "Fixtures"
            ],
            sources: ["Tests"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
