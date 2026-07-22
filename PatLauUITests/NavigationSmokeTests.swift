import XCTest

final class NavigationSmokeTests: XCTestCase {
    func testColdLaunchStartsAtLogin() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Sign in"].exists)
        XCTAssertFalse(app.navigationBars["Home"].exists)

        let emailBox = app.descendants(matching: .any)["login-email-container"]
            .firstMatch
        let passwordBox = app.descendants(matching: .any)["login-password-container"]
            .firstMatch
        XCTAssertTrue(emailBox.exists)
        XCTAssertTrue(passwordBox.exists)
        XCTAssertEqual(emailBox.frame.width, passwordBox.frame.width, accuracy: 0.5)
        XCTAssertEqual(emailBox.frame.height, passwordBox.frame.height, accuracy: 0.5)
    }

    func testProgrammeDirectoryAndNativeAttendanceNavigation() throws {
        let app = launchApp()

        guard app.navigationBars["Home"].waitForExistence(timeout: 8) else {
            throw XCTSkip("A signed-in test account is required for authenticated navigation checks.")
        }

        let weekend = app.staticTexts["Weekend"]
        XCTAssertTrue(weekend.waitForExistence(timeout: 8))
        weekend.tap()

        XCTAssertTrue(app.navigationBars["Weekend"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Weekend Dashboard"].exists)
        XCTAssertTrue(app.staticTexts["Add Weekend Student"].exists)
        XCTAssertFalse(app.staticTexts["Open (group.title)"].exists)
        keepScreenshot(of: app, name: "Weekend Directory")

        let attendance = app.staticTexts["Weekend Attendance"]
        XCTAssertTrue(attendance.exists)
        attendance.tap()

        XCTAssertTrue(app.navigationBars["Attendance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Search Weekend student by name"].exists)
        XCTAssertTrue(app.staticTexts["Filter students"].exists)
        XCTAssertTrue(app.buttons["All days"].exists)
        XCTAssertFalse(app.staticTexts["Chats"].exists)
        XCTAssertFalse(app.staticTexts["Makeup"].exists)

        let attendanceAction = app.staticTexts["Tap to update attendance"].firstMatch
        if attendanceAction.waitForExistence(timeout: 3) {
            attendanceAction.tap()
            XCTAssertTrue(app.staticTexts["Update Attendance"].waitForExistence(timeout: 4))
            XCTAssertTrue(app.staticTexts["Recent Attendance"].exists)
            keepScreenshot(of: app, name: "Attendance Actions")
        }
    }

    func testSessionAttendanceReportShowsDailyStudentsAndSummary() throws {
        let app = launchApp(arguments: [
            "-uiTestingRole=member",
            "-uiTestingSessionReports"
        ])

        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        app.staticTexts["Weekend"].tap()

        let reports = app.staticTexts["Weekend Session Reports"]
        XCTAssertTrue(reports.waitForExistence(timeout: 4))
        reports.tap()

        XCTAssertTrue(app.navigationBars["Session Reports"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Weekend Attendance Report"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["Selected day"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["All records"].exists)
        XCTAssertTrue(app.otherElements["attendance-report-summary"].exists)
        XCTAssertTrue(app.staticTexts["Saturday • 2-4pm"].exists)
        XCTAssertTrue(app.staticTexts["Brendan Lau"].exists)
        XCTAssertTrue(app.staticTexts["Nicholas Lau"].exists)
        XCTAssertTrue(app.staticTexts["Attended"].exists)
        XCTAssertTrue(app.staticTexts["Missed"].exists)
        XCTAssertTrue(app.buttons["Refresh Weekend session reports"].exists)

        let dateButton = app.buttons["session-attendance-report-date-button"]
        XCTAssertTrue(dateButton.exists)
        dateButton.tap()
        XCTAssertTrue(app.staticTexts["Choose a Date"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.datePickers["attendance-date-picker"].exists)
        XCTAssertEqual(app.buttons["attendance-date-cancel"].label, "Cancel")
        app.buttons["attendance-date-cancel"].tap()

        keepScreenshot(of: app, name: "Weekend Session Attendance Report")
    }

    func testWeekendAttendanceFailureAppearsAboveActionSheet() throws {
        let app = launchApp(arguments: ["-uiTestingAttendanceError"])

        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 8))
        app.staticTexts["Weekend"].tap()
        XCTAssertTrue(app.staticTexts["Weekend Attendance"].waitForExistence(timeout: 4))
        app.staticTexts["Weekend Attendance"].tap()

        let attendanceAction = app.staticTexts["Tap to update attendance"].firstMatch
        XCTAssertTrue(attendanceAction.waitForExistence(timeout: 5))
        attendanceAction.tap()

        let markAttended = app.buttons["Mark Attended"]
        XCTAssertTrue(markAttended.waitForExistence(timeout: 4))
        markAttended.tap()

        let alert = app.alerts["Unable to Update Attendance"]
        XCTAssertTrue(
            alert.waitForExistence(timeout: 5),
            "A failed attendance action must show its explanation above the open sheet."
        )
        XCTAssertTrue(
            alert.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'Today is'")
            ).firstMatch.exists
        )
        XCTAssertTrue(alert.buttons["OK"].exists)
        keepScreenshot(of: app, name: "Attendance Error Alert")
    }

    func testAttendanceCanChooseAnEarlierLessonDate() throws {
        let app = launchApp(arguments: [
            "-uiTestingRole=member",
            "-uiTestingAttendanceError"
        ])

        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        app.staticTexts["Weekend"].tap()
        XCTAssertTrue(app.staticTexts["Weekend Attendance"].waitForExistence(timeout: 4))
        app.staticTexts["Weekend Attendance"].tap()

        let attendanceAction = app.staticTexts["Tap to update attendance"].firstMatch
        XCTAssertTrue(attendanceAction.waitForExistence(timeout: 5))
        attendanceAction.tap()

        let anotherDate = app.buttons["mark-attended-another-date"]
        XCTAssertTrue(anotherDate.waitForExistence(timeout: 4))
        anotherDate.tap()

        XCTAssertTrue(app.staticTexts["Mark Another Date"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Historical attendance"].exists)
        XCTAssertTrue(app.datePickers["historical-attendance-date-picker"].exists)
        XCTAssertTrue(app.buttons["confirm-historical-attendance"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'Choose the actual lesson date'")
            ).firstMatch.exists
        )
        keepScreenshot(of: app, name: "Historical Attendance Date")
    }

    func testWeekdayAttendanceCanShowOneDateOrAllScheduledDays() throws {
        let app = launchApp(arguments: [
            "-uiTestingRole=superuser",
            "-uiTestingWeekdayAttendance"
        ])

        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        app.staticTexts["Weekday"].tap()
        XCTAssertTrue(app.staticTexts["Weekday Attendance"].waitForExistence(timeout: 4))
        app.staticTexts["Weekday Attendance"].tap()

        XCTAssertTrue(app.navigationBars["Attendance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.datePickers["attendance-lesson-date"].exists)
        let scope = app.segmentedControls["weekday-attendance-scope"]
        XCTAssertTrue(scope.buttons["Selected date"].exists)
        XCTAssertTrue(scope.buttons["All scheduled days"].exists)

        scope.buttons["All scheduled days"].tap()
        XCTAssertTrue(app.buttons["Monday"].exists)
        XCTAssertTrue(app.buttons["Wednesday"].exists)
        XCTAssertTrue(app.buttons["Thursday"].exists)
        XCTAssertTrue(app.staticTexts["Brandon Teo"].exists)
        XCTAssertTrue(app.staticTexts["Monday Student"].exists)

        app.buttons["Wednesday"].tap()
        XCTAssertTrue(app.staticTexts["Brandon Teo"].exists)
        XCTAssertFalse(app.staticTexts["Monday Student"].exists)
        XCTAssertTrue(app.staticTexts["Wednesday · 2 hours"].exists)
        keepScreenshot(of: app, name: "Weekday Attendance Filters")
    }

    func testWeekdayDashboardMatchesJulyMonthlyPaymentCalculation() throws {
        let app = launchApp(arguments: [
            "-uiTestingRole=superuser",
            "-uiTestingWeekdayDashboard"
        ])

        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        app.staticTexts["Weekday"].tap()
        XCTAssertTrue(app.staticTexts["Weekday Dashboard"].waitForExistence(timeout: 4))
        app.staticTexts["Weekday Dashboard"].tap()

        XCTAssertTrue(app.navigationBars["Weekday Dashboard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Brandon Teo"].exists)
        XCTAssertTrue(app.staticTexts["Monthly Payable Hours"].exists)
        XCTAssertTrue(app.staticTexts["15"].exists)
        XCTAssertTrue(app.staticTexts["Total Payment Amount"].exists)
        XCTAssertTrue(app.staticTexts["1200"].exists)
        XCTAssertTrue(app.staticTexts["July 2026"].exists)
        keepScreenshot(of: app, name: "Weekday Dashboard Monthly Total")
    }

    func testLongDirectoryCanScrollItsLastRecordAboveTheTabBar() throws {
        let app = launchApp(arguments: [
            "-uiTestingRole=member",
            "-uiTestingLongAttendanceList"
        ])

        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        app.staticTexts["Weekend"].tap()
        XCTAssertTrue(app.staticTexts["Weekend Attendance"].waitForExistence(timeout: 4))
        app.staticTexts["Weekend Attendance"].tap()
        XCTAssertTrue(app.navigationBars["Attendance"].waitForExistence(timeout: 5))

        let lastRecord = app.buttons["attendance-record-ui-test-long-student-14"]
        for _ in 0..<18 where !lastRecord.isHittable {
            app.swipeUp(velocity: .fast)
        }

        XCTAssertTrue(
            lastRecord.isHittable,
            "The final database record must be reachable by normal vertical scrolling."
        )

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists)
        XCTAssertLessThanOrEqual(
            lastRecord.frame.maxY,
            tabBar.frame.minY + 1,
            "The final record must scroll completely above the floating tab bar."
        )
        keepScreenshot(of: app, name: "Long Directory Final Record")
    }

    func testQuickAccessEditorSupportsFiveOrFewerShortcuts() throws {
        let app = launchApp()

        guard app.navigationBars["Home"].waitForExistence(timeout: 8) else {
            throw XCTSkip("A signed-in test account is required for authenticated navigation checks.")
        }

        let edit = app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()

        XCTAssertTrue(app.staticTexts["Quick Access"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Your shortcuts ('")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Save"].exists)
    }

    func testHomeAttendanceIsVisibleAboveProgrammesForEveryRole() throws {
        for role in ["member", "admin", "superuser"] {
            let app = launchApp(arguments: ["-uiTestingRole=\(role)"])

            XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Attendance"].firstMatch.exists)
            XCTAssertTrue(app.staticTexts["My Coaching Attendance"].firstMatch.exists)

            if role == "superuser" {
                XCTAssertTrue(app.staticTexts["All Attendance"].firstMatch.exists)
            } else {
                XCTAssertFalse(app.staticTexts["All Attendance"].firstMatch.exists)
            }

            let attendanceRow = app.staticTexts["My Coaching Attendance"].firstMatch
            let programmes = app.staticTexts["Programmes"].firstMatch
            XCTAssertTrue(attendanceRow.exists)
            XCTAssertTrue(programmes.exists)
            XCTAssertLessThan(
                attendanceRow.frame.minY,
                programmes.frame.minY,
                "Attendance should appear above Programmes on Home."
            )

            app.terminate()
        }
    }

    func testCoachingAttendanceFiltersBySpecificDateOrAllRecords() throws {
        let app = launchApp(arguments: ["-uiTestingRole=member"])

        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        let attendance = app.staticTexts["My Coaching Attendance"].firstMatch
        XCTAssertTrue(attendance.waitForExistence(timeout: 4))
        attendance.tap()

        XCTAssertTrue(app.navigationBars["My Attendance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls.buttons["Specific Date"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["All Records"].exists)

        let dateButton = app.buttons["attendance-date-button"]
        XCTAssertTrue(dateButton.exists)
        dateButton.tap()
        XCTAssertTrue(app.staticTexts["Choose a Date"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.datePickers["attendance-date-picker"].exists)
        let cancel = app.buttons["attendance-date-cancel"]
        XCTAssertTrue(cancel.exists)
        XCTAssertEqual(cancel.label, "Cancel")
        keepScreenshot(of: app, name: "Attendance Date Picker")
        cancel.tap()

        app.segmentedControls.buttons["All Records"].tap()
        XCTAssertFalse(app.buttons["attendance-date-button"].exists)
        XCTAssertTrue(
            app.staticTexts["Showing every available coaching attendance record."].exists
        )
        keepScreenshot(of: app, name: "Attendance Record Filter")
    }

    func testDatabaseBackedDirectoriesExposeManualRefresh() throws {
        let app = launchApp()

        guard app.navigationBars["Home"].waitForExistence(timeout: 8) else {
            throw XCTSkip("A signed-in test account is required for authenticated navigation checks.")
        }

        XCTAssertTrue(
            app.buttons["data-refresh"].waitForExistence(timeout: 4),
            "The Home programme counts should be manually refreshable."
        )

        app.staticTexts["Weekend"].tap()
        app.staticTexts["Weekend Dashboard"].tap()
        XCTAssertTrue(app.navigationBars["Weekend Dashboard"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons["data-refresh"].exists,
            "Student dashboards should provide a refresh button beside their record count."
        )
        let obsoleteActiveColumnError = app.staticTexts.matching(
            NSPredicate(
                format: "label CONTAINS[c] 'active' AND label CONTAINS[c] 'does not exist'"
            )
        ).firstMatch
        XCTAssertFalse(
            obsoleteActiveColumnError.waitForExistence(timeout: 3),
            "Weekend Dashboard must not expose a stale student.active schema error."
        )
        keepScreenshot(of: app, name: "Weekend Dashboard Refresh")

        app.navigationBars["Weekend Dashboard"].buttons.firstMatch.tap()
        app.staticTexts["Weekend Attendance"].tap()
        XCTAssertTrue(app.navigationBars["Attendance"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons["data-refresh"].exists,
            "Attendance directories should provide a manual refresh button."
        )

        app.navigationBars["Attendance"].buttons.firstMatch.tap()
        app.staticTexts["Weekend Payments"].tap()
        XCTAssertTrue(app.navigationBars["Weekend Payments"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Quarterly tracking period"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'rolling three-month quarter'")
            ).firstMatch.exists
        )
        XCTAssertTrue(
            app.buttons["data-refresh"].exists,
            "Payment directories should provide a manual refresh button."
        )
        XCTAssertTrue(
            app.buttons["Refresh Weekend payments"].exists,
            "The Weekend payment refresh must identify its specific dataset."
        )
    }

    func testSuperuserCanOpenNativeChatsAndAuditLogs() throws {
        let app = launchApp()

        guard app.navigationBars["Home"].waitForExistence(timeout: 8) else {
            throw XCTSkip("A signed-in test account is required for authenticated navigation checks.")
        }

        let homeSection = app.staticTexts["Chats & audit records"]
        let homeChats = app.staticTexts["Parent Support Chats"]
        let homeAuditLogs = app.staticTexts["Audit Logs"]
        XCTAssertTrue(
            homeSection.waitForExistence(timeout: 5),
            "Superusers should have a permanent Chats and Audit Logs section on Home."
        )
        XCTAssertTrue(homeChats.exists)
        XCTAssertTrue(homeAuditLogs.exists)
        keepScreenshot(of: app, name: "Home Chats and Audit Logs")

        homeChats.tap()
        XCTAssertTrue(app.navigationBars["Chats"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Inbox"].exists)
        XCTAssertTrue(app.buttons["Refresh parent support inbox"].exists)
        let supportAccessError = app.staticTexts.matching(
            NSPredicate(
                format: "label CONTAINS[c] '403' OR label CONTAINS[c] 'permission denied'"
            )
        ).firstMatch
        XCTAssertFalse(
            supportAccessError.waitForExistence(timeout: 3),
            "Chats must load through the protected support API without a table-level 403."
        )

        app.buttons["Knowledge"].tap()
        XCTAssertTrue(
            app.buttons["Refresh support knowledge"].waitForExistence(timeout: 4)
        )

        app.buttons["Announcements"].tap()
        XCTAssertTrue(
            app.buttons["Refresh support announcements"].waitForExistence(timeout: 4)
        )
        app.navigationBars["Chats"].buttons.firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 4))
        let auditLogs = app.staticTexts["Audit Logs"]
        XCTAssertTrue(auditLogs.waitForExistence(timeout: 4))
        auditLogs.tap()
        XCTAssertTrue(app.navigationBars["Audit Logs"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Recent Supabase activity"].exists)
        XCTAssertTrue(app.staticTexts["Audit export health"].exists)
        keepScreenshot(of: app, name: "Chats and Audit Logs")
    }

    func testSuperuserCanOpenNativeMakeupTracker() throws {
        let app = launchApp()

        guard app.navigationBars["Home"].waitForExistence(timeout: 8) else {
            throw XCTSkip("A signed-in test account is required for authenticated navigation checks.")
        }

        let makeup = app.staticTexts["My Makeup"].firstMatch
        guard makeup.waitForExistence(timeout: 4) else {
            throw XCTSkip("The signed-in UI-test account is not a superuser.")
        }
        XCTAssertTrue(app.staticTexts["Makeup Payments"].firstMatch.exists)

        makeup.tap()
        XCTAssertTrue(app.navigationBars["My Makeup"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Makeup Payments"].firstMatch.exists)
        XCTAssertTrue(app.segmentedControls.buttons["Available"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["Usage"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["History"].exists)
        XCTAssertTrue(app.textFields["Search student, programme or status"].exists)
        keepScreenshot(of: app, name: "My Makeup Tracker")
    }

    func testMakeupPaymentCounterActionsMatchProgrammePayments() throws {
        let app = launchApp()

        guard app.navigationBars["Home"].waitForExistence(timeout: 8) else {
            throw XCTSkip("A signed-in test account is required for authenticated navigation checks.")
        }

        let makeupPayments = app.staticTexts["Makeup Payments"].firstMatch
        guard makeupPayments.waitForExistence(timeout: 5) else {
            throw XCTSkip("The signed-in UI-test account cannot access Makeup Payments.")
        }
        makeupPayments.tap()

        XCTAssertTrue(app.navigationBars["Makeup Payments"].waitForExistence(timeout: 5))
        let reset = app.buttons["payment-reset-total"]
        let undo = app.buttons["payment-undo-latest"]
        XCTAssertTrue(reset.waitForExistence(timeout: 4))
        XCTAssertTrue(undo.exists)

        reset.tap()
        let alert = app.alerts["Reset the displayed total?"]
        XCTAssertTrue(
            alert.waitForExistence(timeout: 4),
            "Makeup payment confirmations should appear in the centre like the other payment screens."
        )
        XCTAssertTrue(alert.buttons["Send Summary and Reset"].exists)
        alert.buttons["Cancel"].tap()
        keepScreenshot(of: app, name: "Makeup Payment Counter Actions")
    }

    func testVoidCreditUsesCenteredConfirmationAlert() throws {
        let app = launchApp()

        guard app.navigationBars["Home"].waitForExistence(timeout: 8) else {
            throw XCTSkip("A signed-in test account is required for authenticated navigation checks.")
        }

        let makeup = app.staticTexts["My Makeup"].firstMatch
        guard makeup.waitForExistence(timeout: 4) else {
            throw XCTSkip("The signed-in UI-test account is not a superuser.")
        }
        makeup.tap()

        let voidButton = app.buttons["Void credit"].firstMatch
        guard voidButton.waitForExistence(timeout: 5) else {
            throw XCTSkip("An available makeup credit is required for the confirmation check.")
        }

        voidButton.tap()
        let alert = app.alerts["Void Makeup Credit?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 4))
        XCTAssertTrue(alert.buttons["Void Credit"].exists)
        XCTAssertTrue(alert.buttons["Cancel"].exists)
        keepScreenshot(of: app, name: "Void Makeup Credit Confirmation")
        alert.buttons["Cancel"].tap()
    }

    func testAccountDoesNotShowWebsiteTab() throws {
        let app = launchApp()

        guard app.navigationBars["Home"].waitForExistence(timeout: 8) else {
            throw XCTSkip("A signed-in test account is required for authenticated navigation checks.")
        }

        app.tabBars.buttons["Account"].tap()
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Website"].exists)
        XCTAssertFalse(app.staticTexts["Website"].exists)
    }

    func testTelegramAdministratorManagementIsSuperuserOnly() throws {
        let superuserApp = launchApp(arguments: [
            "-uiTestingRole=superuser",
            "-uiTestingTelegramAdministrators"
        ])

        XCTAssertTrue(superuserApp.navigationBars["Home"].waitForExistence(timeout: 5))
        superuserApp.tabBars.buttons["Account"].tap()
        XCTAssertTrue(superuserApp.navigationBars["Account"].waitForExistence(timeout: 5))

        let manager = superuserApp.staticTexts["Telegram Administrators"]
        XCTAssertTrue(manager.waitForExistence(timeout: 4))
        manager.tap()
        XCTAssertTrue(superuserApp.navigationBars["Telegram Administrators"].waitForExistence(timeout: 4))
        XCTAssertTrue(superuserApp.staticTexts["How to connect an account"].exists)
        XCTAssertTrue(superuserApp.staticTexts["Add Telegram Administrator"].exists)
        XCTAssertTrue(superuserApp.staticTexts["All Administrators"].exists)
        XCTAssertTrue(superuserApp.staticTexts["2 active"].exists)
        XCTAssertTrue(superuserApp.staticTexts["Primary Administrator"].exists)
        XCTAssertTrue(superuserApp.staticTexts["Telegram ID ••••••3766"].exists)
        XCTAssertTrue(superuserApp.staticTexts["PRIMARY"].exists)
        XCTAssertTrue(superuserApp.staticTexts["Weekend Support Admin"].exists)
        XCTAssertTrue(superuserApp.staticTexts["Telegram ID •••••6789"].exists)
        XCTAssertTrue(superuserApp.staticTexts["ACTIVE"].exists)
        XCTAssertFalse(superuserApp.buttons["Actions for Primary Administrator"].exists)
        XCTAssertTrue(superuserApp.buttons["Actions for Weekend Support Admin"].exists)
        keepScreenshot(of: superuserApp, name: "All Telegram Administrators")
        superuserApp.terminate()

        let memberApp = launchApp(arguments: ["-uiTestingRole=member"])
        XCTAssertTrue(memberApp.navigationBars["Home"].waitForExistence(timeout: 5))
        memberApp.tabBars.buttons["Account"].tap()
        XCTAssertTrue(memberApp.navigationBars["Account"].waitForExistence(timeout: 5))
        XCTAssertFalse(memberApp.staticTexts["Telegram Administrators"].exists)
    }

    func testConversationUniversalLinkIsRoleProtected() throws {
        let conversationID = "7cda7535-f22d-405e-a996-12f9c30db44d"
        let superuserApp = launchApp(arguments: [
            "-uiTestingRole=superuser",
            "-uiTestingConversation=\(conversationID)"
        ])

        XCTAssertTrue(
            superuserApp.navigationBars["Parent Conversation"]
                .waitForExistence(timeout: 6)
        )
        XCTAssertTrue(superuserApp.tabBars.buttons["Operations"].isSelected)
        superuserApp.terminate()

        let memberApp = launchApp(arguments: [
            "-uiTestingRole=member",
            "-uiTestingConversation=\(conversationID)"
        ])

        XCTAssertTrue(memberApp.navigationBars["Home"].waitForExistence(timeout: 5))
        XCTAssertFalse(memberApp.navigationBars["Parent Conversation"].exists)
        XCTAssertTrue(
            memberApp.staticTexts[
                "Superuser access is required to open parent conversations."
            ].waitForExistence(timeout: 4)
        )
    }

    func testAddStudentIsAStandalonePage() throws {
        let app = launchApp()

        guard app.navigationBars["Home"].waitForExistence(timeout: 8) else {
            throw XCTSkip("A signed-in test account is required for authenticated navigation checks.")
        }

        app.staticTexts["Weekend"].tap()
        app.staticTexts["Add Weekend Student"].tap()

        XCTAssertTrue(app.navigationBars["Add Weekend Student"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Cancel"].exists)
        XCTAssertTrue(app.staticTexts["Student Level of Play"].exists)
        keepScreenshot(of: app, name: "Add Weekend Student")
    }

    func testFullWebsiteHidesNativeTabBarAndKeepsOnlyTopRefreshControl() throws {
        let app = launchApp()

        guard app.navigationBars["Home"].waitForExistence(timeout: 8) else {
            throw XCTSkip("A signed-in test account is required for authenticated navigation checks.")
        }

        app.tabBars.buttons["Operations"].tap()
        app.staticTexts["Full Web Portal"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Full Web Portal"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.tabBars.buttons["Home"].exists)
        XCTAssertFalse(app.buttons["Back"].exists)
        XCTAssertFalse(app.buttons["Forward"].exists)
        XCTAssertTrue(app.buttons["Reload"].exists)
    }

    func testWeekdayDashboardAndAddStudentAreSeparate() throws {
        let app = launchApp()

        guard app.navigationBars["Home"].waitForExistence(timeout: 8) else {
            throw XCTSkip("A signed-in test account is required for authenticated navigation checks.")
        }

        app.staticTexts["Weekday"].tap()
        XCTAssertTrue(app.staticTexts["Weekday Dashboard"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Add Weekday Student"].exists)
        app.staticTexts["Weekday Dashboard"].tap()
        XCTAssertTrue(app.navigationBars["Weekday Dashboard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add"].exists)
    }

    func testPaymentActionsAreCompactAndConfirmationIsCentered() throws {
        let app = launchApp()

        guard app.navigationBars["Home"].waitForExistence(timeout: 8) else {
            throw XCTSkip("A signed-in test account is required for authenticated navigation checks.")
        }

        app.staticTexts["Weekday"].tap()
        app.staticTexts["Weekday Payments"].tap()

        XCTAssertTrue(app.navigationBars["Weekday Payments"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Monthly tracking period"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'calendar month'")
            ).firstMatch.exists
        )

        let action = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Payment actions for'")
        ).firstMatch
        guard action.waitForExistence(timeout: 6) else {
            throw XCTSkip("A disposable Weekday student is required for payment interaction checks.")
        }

        action.tap()
        let paymentAction = app.buttons["Mark Paid"].exists
            ? app.buttons["Mark Paid"]
            : app.buttons["Mark Unpaid"]
        paymentAction.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 4))
        keepScreenshot(of: app, name: "Payment Confirmation")
        app.alerts.buttons["Cancel"].tap()

        action.tap()
        app.buttons["Adjust Payment"].tap()
        XCTAssertTrue(app.staticTexts["Adjust Payment"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Payable hours"].exists)
        keepScreenshot(of: app, name: "Weekday Payable Hours")
    }

    func testOneToOneShowsEverySundayWithInlinePairing() throws {
        let app = launchApp()

        guard app.navigationBars["Home"].waitForExistence(timeout: 8) else {
            throw XCTSkip("A signed-in test account is required for authenticated navigation checks.")
        }

        app.staticTexts["1-1"].tap()
        app.staticTexts["1-1 Training & Attendance"].tap()

        XCTAssertTrue(app.navigationBars["1-1 Training"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Add pair"].firstMatch.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'coach-picker-'")
        ).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'student-picker-'")
        ).firstMatch.exists)
        keepScreenshot(of: app, name: "1-1 Monthly Pairing")
    }

    func testStudentDetailsExposeDeleteAction() throws {
        let app = launchApp()

        guard app.navigationBars["Home"].waitForExistence(timeout: 8) else {
            throw XCTSkip("A signed-in test account is required for authenticated navigation checks.")
        }

        app.staticTexts["Weekend"].tap()
        app.staticTexts["Weekend Dashboard"].tap()

        let firstStudent = app.scrollViews.descendants(matching: .staticText)
            .matching(NSPredicate(format: "label != 'Weekend' AND label != 'Weekend Dashboard'"))
            .firstMatch
        guard firstStudent.waitForExistence(timeout: 5) else {
            throw XCTSkip("A disposable Weekend student is required for delete-control checks.")
        }

        // The dashboard's student cards are navigation links. Select a known
        // card title when the shared simulator contains seeded test data.
        let seededStudent = app.staticTexts["Brendan Lau"].firstMatch
        guard seededStudent.exists else {
            throw XCTSkip("Seeded Weekend student is unavailable.")
        }
        seededStudent.tap()
        for _ in 0..<3 where !app.buttons["Delete student"].exists {
            app.swipeUp()
        }
        XCTAssertFalse(
            app.staticTexts["Attendance Records"].exists,
            "Nested attendance records should not render as an empty dash in student details."
        )
        XCTAssertTrue(app.buttons["Delete student"].waitForExistence(timeout: 5))
    }

    func testNoticeDoesNotDisplaceNavigationContent() throws {
        let app = launchApp(arguments: ["-uiTestingNotice"])

        let notice = app.staticTexts["Profile photo updated."]
        XCTAssertTrue(notice.waitForExistence(timeout: 4))

        let navigationBar = app.navigationBars["Home"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 4))
        let title = navigationBar.staticTexts["Home"]
        XCTAssertTrue(title.exists)
        XCTAssertLessThan(
            navigationBar.frame.minY,
            100,
            "A notification must not create an empty region above the page."
        )
        XCTAssertGreaterThanOrEqual(notice.frame.minY, title.frame.maxY)
        let toolbarButton = navigationBar.buttons.firstMatch
        XCTAssertTrue(toolbarButton.exists)
        XCTAssertFalse(notice.frame.intersects(toolbarButton.frame))
        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.exists)
        XCTAssertFalse(notice.frame.intersects(homeTab.frame))
        XCTAssertLessThan(
            notice.frame.midY,
            app.frame.midY,
            "Notifications should appear near the top of the page, never from beneath the tab bar."
        )
        XCTAssertLessThan(
            notice.frame.maxY,
            homeTab.frame.minY,
            "Notifications must remain fully above the Home, Operations and Account tabs."
        )
        keepScreenshot(of: app, name: "Safe Area Notice")
    }

    func testPageReturnsToTopAfterNoticeIsDismissed() throws {
        let app = launchApp(arguments: ["-uiTestingNotice"])

        XCTAssertTrue(app.staticTexts["Profile photo updated."].waitForExistence(timeout: 4))
        app.buttons["Dismiss notification"].tap()
        XCTAssertFalse(app.staticTexts["Profile photo updated."].waitForExistence(timeout: 2))

        app.staticTexts["Weekday"].tap()
        app.staticTexts["Weekday Dashboard"].tap()

        let navigationBar = app.navigationBars["Weekday Dashboard"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
        XCTAssertLessThan(
            navigationBar.frame.minY,
            100,
            "The page should not retain an empty notification region above its navigation bar."
        )
        keepScreenshot(of: app, name: "Dashboard Without Top Gap")
    }

    func testOperationProgressClearlyBlocksDuplicateActions() throws {
        let app = launchApp(arguments: ["-uiTestingActivity"])

        XCTAssertTrue(
            app.staticTexts["Updating attendance status…"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Please wait. This may take a moment."].exists)
        app.tabBars.buttons["Account"].tap()
        XCTAssertTrue(app.navigationBars["Home"].exists)
        XCTAssertFalse(app.navigationBars["Account"].exists)
        keepScreenshot(of: app, name: "Operation Progress")
    }

    func testAdminSeesOperationalToolsWithoutDashboardsOrPayments() throws {
        let app = launchApp(arguments: ["-uiTestingRole=admin"])

        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        app.staticTexts["Weekend"].tap()
        XCTAssertTrue(app.staticTexts["Weekend Attendance"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Add Weekend Student"].exists)
        XCTAssertTrue(app.staticTexts["Coach Attendance Poll"].exists)
        XCTAssertFalse(app.staticTexts["Weekend Dashboard"].exists)
        XCTAssertFalse(app.staticTexts["Weekend Payments"].exists)

        app.navigationBars.buttons.firstMatch.tap()
        app.staticTexts["1-1"].tap()
        XCTAssertTrue(app.staticTexts["Add 1-1 Student"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["1-1 Training & Attendance"].exists)
        XCTAssertFalse(app.staticTexts["1-1 Student Dashboard"].exists)
        XCTAssertFalse(app.staticTexts["1-1 Payments"].exists)

        app.tabBars.buttons["Operations"].tap()
        XCTAssertTrue(app.staticTexts["Support & Attendance"].waitForExistence(timeout: 4))
        app.staticTexts["Support & Attendance"].tap()
        XCTAssertTrue(app.staticTexts["My Coaching Attendance"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["Parent Support Chats"].exists)
        XCTAssertFalse(app.staticTexts["Audit Logs"].exists)
        keepScreenshot(of: app, name: "Admin Role Access")
    }

    func testMemberSeesAttendanceOnly() throws {
        let app = launchApp(arguments: ["-uiTestingRole=member"])

        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["1-1"].exists)
        app.staticTexts["Weekend"].tap()
        XCTAssertTrue(app.staticTexts["Weekend Attendance"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["Weekend Dashboard"].exists)
        XCTAssertFalse(app.staticTexts["Add Weekend Student"].exists)
        XCTAssertFalse(app.staticTexts["Coach Attendance Poll"].exists)
        XCTAssertFalse(app.staticTexts["Weekend Payments"].exists)

        app.tabBars.buttons["Operations"].tap()
        XCTAssertFalse(app.staticTexts["Weekday"].exists)
        XCTAssertFalse(app.staticTexts["MatchPlay"].exists)
        XCTAssertTrue(app.staticTexts["Support & Attendance"].waitForExistence(timeout: 4))
        app.staticTexts["Support & Attendance"].tap()
        XCTAssertTrue(app.staticTexts["My Coaching Attendance"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["Parent Support Chats"].exists)
        XCTAssertFalse(app.staticTexts["Audit Logs"].exists)

        app.tabBars.buttons["Account"].tap()
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Profile Photo"].exists)
        keepScreenshot(of: app, name: "Member Attendance Access")
    }

    func testCoachPollIncludesTelegramPreview() throws {
        let app = launchApp()

        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 5))
        app.staticTexts["Weekend"].tap()
        app.staticTexts["Coach Attendance Poll"].tap()

        let previewTitle = app.staticTexts["Telegram Preview"]
        for _ in 0..<3 where !previewTitle.exists {
            app.swipeUp()
        }
        XCTAssertTrue(previewTitle.waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Opening message"].exists)
        XCTAssertTrue(app.staticTexts["Closing message"].exists)
        keepScreenshot(of: app, name: "Coach Poll Preview")
    }

    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + arguments
        app.launch()
        return app
    }

    private func keepScreenshot(of app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
