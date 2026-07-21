import XCTest
@testable import PatLau

final class CoreTests: XCTestCase {
    @MainActor
    func testColdLaunchRequiresFreshLogin() {
        let state = AppState()
        XCTAssertNil(state.session)
        XCTAssertEqual(state.role, .member)
    }

    func testJSONValueRoundTrip() throws {
        let original = JSONValue.object(["name": .string("Nicholas"), "paid": .bool(true), "hours": .number(2.5)])
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: data), original)
    }

    func testTrackedAuditExportReceiptRequiresSearchableRunID() throws {
        let response = JSONValue.object([
            "success": .bool(true),
            "result": .object([
                "claimed": .number(3),
                "exported": .number(3),
                "pruned": .number(0),
                "requeued": .number(1),
                "batches": .number(1),
                "exportRunId": .string("run-123")
            ])
        ])

        let receipt = try AuditExportReceipt(response: response)
        XCTAssertEqual(receipt.exported, 3)
        XCTAssertEqual(receipt.requeued, 1)
        XCTAssertEqual(receipt.searchQuery, "audit_export_run_id:run-123")
    }

    func testAuditExportReceiptRejectsLegacyUntrackedResponse() {
        let response = JSONValue.object([
            "success": .bool(true),
            "result": .object([
                "claimed": .number(3),
                "exported": .number(3),
                "pruned": .number(0),
                "requeued": .number(0),
                "batches": .number(1)
            ])
        ])

        XCTAssertThrowsError(try AuditExportReceipt(response: response)) { error in
            XCTAssertTrue(error.localizedDescription.contains("run ID"))
        }
    }

    func testSentryProbeReceiptRequiresTrackedSDKAcceptance() throws {
        let response = JSONValue.object([
            "success": .bool(true),
            "result": .object([
                "probeId": .string("probe-123"),
                "sdk": .object([
                    "initialized": .bool(true),
                    "logsEnabled": .bool(true),
                    "queueDrained": .bool(true),
                    "transportAccepted": .bool(true),
                    "deliveryBatchId": .string("batch-123"),
                    "error": .null
                ])
            ])
        ])

        let receipt = try SentryProbeReceipt(response: response)
        XCTAssertEqual(
            receipt.searchQuery,
            "source:patlau_sentry_probe probe_id:probe-123"
        )
    }

    func testDynamicSearchMatchesAnyTextField() {
        let record = DynamicRecord(values: ["id": .string("1"), "title": .string("Makeup policy"), "status": .string("published")])
        XCTAssertTrue(record.matches("makeup"))
        XCTAssertTrue(record.matches("PUBLISHED"))
        XCTAssertFalse(record.matches("weekday fees"))
    }

    func testStudentRecordDetailsHideNonDisplayableNestedValues() {
        let values: JSONObject = [
            "attendance_records": .array([]),
            "metadata": .object(["source": .string("legacy")]),
            "notes": .string("   "),
            "deleted_at": .null,
            "attended": .number(1),
            "paid": .bool(false)
        ]

        XCTAssertEqual(
            StudentRecordDetailFormatter.displayableKeys(in: values),
            ["attended", "paid"]
        )
    }

    func testDynamicRecordFallbackIdentityIsStable() {
        let record = DynamicRecord(values: ["title": .string("No backend ID")])
        XCTAssertEqual(record.id, record.id)
        XCTAssertFalse(record.id.isEmpty)
    }

    func testLegacyPaymentRowsForOneStudentHaveDistinctIdentities() {
        let first = DynamicRecord(values: [
            "student_id": .string("student-1"),
            "amount": .number(80),
            "recorded_at": .string("2026-07-01T10:00:00Z")
        ])
        let second = DynamicRecord(values: [
            "student_id": .string("student-1"),
            "amount": .number(80),
            "recorded_at": .string("2026-07-08T10:00:00Z")
        ])
        XCTAssertNotEqual(first.id, second.id)
    }

    func testDateKeysHaveExpectedShape() {
        XCTAssertEqual(Date(timeIntervalSince1970: 0).isoDateKey.count, 10)
        XCTAssertEqual(Date(timeIntervalSince1970: 0).monthKey.count, 7)
    }

    func testWeekendTimeslotsAreRestrictedByTrainingDay() {
        XCTAssertEqual(WeekendSchedule.timeslots(for: "Saturday"), ["2-4pm", "4-6pm"])
        XCTAssertEqual(
            WeekendSchedule.timeslots(for: "Sunday"),
            ["8-10am", "10-12pm", "1-3pm", "3-5pm"]
        )
        XCTAssertTrue(
            Set(WeekendSchedule.saturdayTimeslots)
                .isDisjoint(with: Set(WeekendSchedule.sundayTimeslots))
        )
    }

    func testWeekendStudentQueriesMirrorLegacyWebsiteWithoutActiveFilter() {
        XCTAssertNil(Programme.weekend.activeStudentFilter)
        XCTAssertTrue(Programme.weekend.includesStudent(active: nil))
        XCTAssertTrue(Programme.weekend.includesStudent(active: false))

        for programme in [Programme.weekday, .matchplay, .oneToOne] {
            XCTAssertEqual(programme.activeStudentFilter?.name, "or")
            XCTAssertEqual(
                programme.activeStudentFilter?.value,
                "(active.is.null,active.eq.true)"
            )
            XCTAssertTrue(programme.includesStudent(active: nil))
            XCTAssertTrue(programme.includesStudent(active: true))
            XCTAssertFalse(programme.includesStudent(active: false))
        }
    }

    func testWeekendAttendanceExplainsWrongTrainingDay() {
        XCTAssertEqual(
            WeekendAttendancePolicy.attendedError(
                studentName: "Brendan Lau",
                trainingDay: "Saturday",
                today: "Tuesday"
            ),
            "Brendan Lau is scheduled for Saturday. Today is Tuesday, so Weekend attendance cannot be marked present yet."
        )
        XCTAssertNil(
            WeekendAttendancePolicy.attendedError(
                studentName: "Brendan Lau",
                trainingDay: "Saturday",
                today: "Saturday"
            )
        )
    }

    func testWeekendAttendanceExplainsMissingSchedule() {
        XCTAssertEqual(
            WeekendAttendancePolicy.attendedError(
                studentName: "Brendan Lau",
                trainingDay: "",
                today: "Tuesday"
            ),
            "Brendan Lau does not have a Weekend training day assigned. Update the student's schedule before marking attendance."
        )
    }

    func testAttendanceRecordFilterSupportsOneDateAndAllRecords() {
        let selectedDate = "2026-07-21"

        XCTAssertTrue(
            AttendanceRecordView.specificDate.includes(
                dateKey: "2026-07-21|8am|12pm",
                selectedDateKey: selectedDate
            )
        )
        XCTAssertTrue(
            AttendanceRecordView.specificDate.includes(
                dateKey: "21/7/2026-8-12",
                selectedDateKey: selectedDate
            )
        )
        XCTAssertFalse(
            AttendanceRecordView.specificDate.includes(
                dateKey: "2026-07-22-8-12",
                selectedDateKey: selectedDate
            )
        )
        XCTAssertTrue(
            AttendanceRecordView.allRecords.includes(
                dateKey: "2025-01-01",
                selectedDateKey: selectedDate
            )
        )
    }

    func testAttendanceDateKeyNormalisesWebsiteAndTelegramFormats() {
        XCTAssertEqual(
            AttendanceDateKey.dateOnly(from: "2026-07-21-8-12"),
            "2026-07-21"
        )
        XCTAssertEqual(
            AttendanceDateKey.dateOnly(from: "2026-07-21|8am|12pm"),
            "2026-07-21"
        )
        XCTAssertEqual(
            AttendanceDateKey.dateOnly(from: "21/7/2026-8-12"),
            "2026-07-21"
        )
        XCTAssertNil(AttendanceDateKey.dateOnly(from: "2026-02-31"))
        XCTAssertNil(AttendanceDateKey.dateOnly(from: "not-a-date"))
    }

    func testCoachingAttendancePayUsesTelegramSlotsAndOneToOneAllocations() {
        XCTAssertEqual(
            CoachingAttendancePay.telegramAmount(dateKey: "2026-07-25"),
            70
        )
        XCTAssertEqual(
            CoachingAttendancePay.telegramAmount(dateKey: "2026-07-25-2-4"),
            70
        )
        XCTAssertEqual(
            CoachingAttendancePay.telegramAmount(dateKey: "2026-07-25-4-6"),
            70
        )
        XCTAssertEqual(
            CoachingAttendancePay.telegramAmount(dateKey: "2026-07-26-8-12"),
            70
        )
        XCTAssertEqual(
            CoachingAttendancePay.telegramAmount(dateKey: "2026-07-26-1-5"),
            70
        )
        XCTAssertEqual(
            CoachingAttendancePay.telegramAmount(dateKey: "2026-07-26-10-12"),
            35
        )
        XCTAssertEqual(
            CoachingAttendancePay.telegramAmount(dateKey: "26/7/2026-3-5"),
            35
        )
        XCTAssertEqual(
            CoachingAttendancePay.amount(
                source: "one_to_one",
                dateKey: "2026-07-26"
            ),
            40
        )
    }

    func testMakeupProgrammeChooserMirrorsWebsiteTargets() {
        XCTAssertEqual(
            Set(MakeupTargetProgramme.allCases.map(\.rawValue)),
            Set(["weekend", "weekday", "one_to_one", "matchplay"])
        )
        XCTAssertEqual(MakeupTargetProgramme.weekend.defaultTargetValue, 40)
        XCTAssertEqual(MakeupTargetProgramme.weekday.defaultTargetValue, 80)
        XCTAssertEqual(MakeupTargetProgramme.oneToOne.title, "1-1")

        let target = MakeupTargetSelection.defaultTarget(
            forSourceType: "one_to_one",
            date: "2026-07-21T08:00:00Z"
        )
        XCTAssertEqual(target.programme, .oneToOne)
        XCTAssertEqual(target.dateKey, "2026-07-21")
    }

    func testRestoredSessionUsesJWTAbsoluteExpiry() throws {
        let json = #"{"access_token":"e30.eyJleHAiOjIwMDAwMDAwMDB9.signature","refresh_token":"refresh","expires_in":3600,"user":{"id":"user-1"}}"#
        let session = try JSONDecoder().decode(AuthSession.self, from: Data(json.utf8))
        XCTAssertEqual(session.expiryDate, Date(timeIntervalSince1970: 2_000_000_000))
    }

    func testPortalOperationsHaveUniqueRoutesAndRoleCoverage() {
        XCTAssertEqual(
            Set(PortalOperation.allCases.map(\.webPath)).count,
            PortalOperation.allCases.count
        )
        XCTAssertTrue(PortalOperation.allCases.allSatisfy { !$0.allowedRoles.isEmpty })
        XCTAssertEqual(
            Set(PortalOperation.visible(for: .member)),
            Set([.weekendAttendance, .myAttendance, .settings])
        )
        XCTAssertEqual(
            Set(PortalOperation.visible(for: .admin)),
            Set([
                .weekendAddStudent, .weekendAttendance, .coachAttendance,
                .oneToOneAddStudent, .oneToOneTraining,
                .myAttendance, .settings
            ])
        )
        XCTAssertTrue(
            PortalOperation.allCases.allSatisfy { $0.isAvailable(for: .superuser) }
        )
        XCTAssertEqual(PortalOperation.makeupCredits.title, "My Makeup")
        XCTAssertEqual(PortalOperation.auditLogs.webPath, "/audit-logs")
        XCTAssertEqual(PortalOperation.auditLogs.allowedRoles, [.superuser])
        XCTAssertEqual(PortalOperation.chats.allowedRoles, [.superuser])
    }

    func testHomeAttendanceIsPermanentAndRoleAware() {
        XCTAssertEqual(
            PortalOperation.homeAttendance(for: .member),
            [.myAttendance]
        )
        XCTAssertEqual(
            PortalOperation.homeAttendance(for: .admin),
            [.myAttendance]
        )
        XCTAssertEqual(
            PortalOperation.homeAttendance(for: .superuser),
            [.myAttendance, .allAttendance]
        )
    }

    func testWeekendPaymentHistorySetupUsesTheSupportedHTTPMethod() {
        XCTAssertEqual(PaymentWebsiteRoute.ensureWeekendHistory, "/api/create-payment-table")
        XCTAssertEqual(PaymentWebsiteRoute.ensureWeekendHistoryMethod, "POST")
    }

    func testWeekendStudentReadsUseMatchingWebsiteServices() {
        XCTAssertEqual(WeekendStudentWebsiteRoute.dashboard, "/api/search")
        XCTAssertEqual(
            WeekendStudentWebsiteRoute.dashboardSources,
            ["/api/search", "/api/payment-search"]
        )
        XCTAssertEqual(
            WeekendStudentWebsiteRoute.attendance,
            "/api/attendance-search"
        )
        XCTAssertEqual(
            WeekendStudentWebsiteRoute.payments,
            "/api/payment-search"
        )
    }

    func testWeekendPaymentQuarterSpansThreeMonthsAndAdvancesInQuarters() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let formatter = ISO8601DateFormatter()
        let july = try XCTUnwrap(formatter.date(from: "2026-07-21T00:00:00Z"))

        let first = WeekendPaymentQuarter.new(startingAt: july, calendar: calendar)
        XCTAssertEqual(first.start, july)
        XCTAssertEqual(
            first.end,
            formatter.date(from: "2026-10-21T00:00:00Z")
        )

        let february = try XCTUnwrap(formatter.date(from: "2027-02-01T00:00:00Z"))
        let advanced = first.advanced(to: february, calendar: calendar)
        XCTAssertEqual(
            advanced.start,
            formatter.date(from: "2027-01-21T00:00:00Z")
        )
        XCTAssertEqual(
            advanced.end,
            formatter.date(from: "2027-04-21T00:00:00Z")
        )
    }

    func testMonthlyPaymentPeriodUsesExactCalendarMonthBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let formatter = ISO8601DateFormatter()
        let july = try XCTUnwrap(formatter.date(from: "2026-07-21T12:30:00Z"))

        let period = CalendarMonthPaymentPeriod.containing(
            july,
            calendar: calendar
        )

        XCTAssertEqual(
            period.start,
            formatter.date(from: "2026-07-01T00:00:00Z")
        )
        XCTAssertEqual(
            period.end,
            formatter.date(from: "2026-08-01T00:00:00Z")
        )
    }

    func testPaymentTrackingCadencesMatchTheWebsite() {
        XCTAssertEqual(
            PaymentRefreshPlan(programme: .weekend).trackingCadence,
            .rollingThreeMonths
        )
        for programme in [Programme.weekday, .matchplay, .oneToOne] {
            XCTAssertEqual(
                PaymentRefreshPlan(programme: programme).trackingCadence,
                .calendarMonth
            )
        }
    }

    func testMonthlyPaymentCounterOnlyIncludesPaidUpdatesSinceReset() throws {
        let formatter = ISO8601DateFormatter()
        let reset = try XCTUnwrap(
            formatter.date(from: "2026-07-21T10:00:00Z")
        )
        let beforeReset = try XCTUnwrap(
            formatter.date(from: "2026-07-21T09:59:59Z")
        )
        let atReset = try XCTUnwrap(
            formatter.date(from: "2026-07-21T10:00:00Z")
        )

        XCTAssertFalse(
            MonthlyPaymentCounter.includes(
                paid: true,
                paymentTimestamp: beforeReset,
                resetAt: reset
            )
        )
        XCTAssertTrue(
            MonthlyPaymentCounter.includes(
                paid: true,
                paymentTimestamp: atReset,
                resetAt: reset
            )
        )
        XCTAssertFalse(
            MonthlyPaymentCounter.includes(
                paid: false,
                paymentTimestamp: atReset,
                resetAt: reset
            )
        )
        XCTAssertFalse(
            MonthlyPaymentCounter.includes(
                paid: true,
                paymentTimestamp: nil,
                resetAt: reset
            )
        )
        XCTAssertTrue(
            MonthlyPaymentCounter.includes(
                paid: true,
                paymentTimestamp: nil,
                resetAt: nil
            )
        )
    }

    func testWeekendPaymentRefreshOnlyIncludesWeekendPaymentResources() {
        let plan = PaymentRefreshPlan(programme: .weekend)

        XCTAssertEqual(plan.label, "Weekend payments")
        XCTAssertEqual(
            plan.resources,
            Set([
                "students",
                "weekend_payment_period_state",
                "payment_history"
            ])
        )
        XCTAssertFalse(plan.resources.contains("weekday_students"))
        XCTAssertFalse(plan.resources.contains("weekday_payments"))
        XCTAssertFalse(plan.resources.contains("matchplay_students"))
        XCTAssertFalse(plan.resources.contains("one_to_one_sessions"))
    }

    func testMonthlyPaymentRefreshPlansIncludeOnlyTheirOwnCounterAndData() {
        XCTAssertEqual(
            PaymentRefreshPlan(programme: .weekday).resources,
            Set([
                "weekday_students",
                "weekday_payments",
                "payment_counter_state"
            ])
        )
        XCTAssertEqual(
            PaymentRefreshPlan(programme: .matchplay).resources,
            Set([
                "matchplay_students",
                "matchplay_payments",
                "payment_counter_state"
            ])
        )
        XCTAssertEqual(
            PaymentRefreshPlan(programme: .oneToOne).resources,
            Set([
                "one_to_one_sessions",
                "one_to_one_students",
                "training_payments",
                "payment_counter_state"
            ])
        )
    }

    func testChatRefreshIsScopedToTheSelectedSupportSection() {
        XCTAssertEqual(SupportWebsiteRoute.summary, "/api/support")
        XCTAssertEqual(
            SupportRefreshSection.inbox.resources,
            Set(["support_conversations", "support_contacts"])
        )
        XCTAssertEqual(
            SupportRefreshSection.knowledge.resources,
            Set(["support_knowledge"])
        )
        XCTAssertEqual(
            SupportRefreshSection.announcements.resources,
            Set(["support_announcements"])
        )
        XCTAssertTrue(
            SupportRefreshSection.allCases.allSatisfy {
                !$0.label.isEmpty
                    && !$0.resources.isEmpty
                    && !$0.responseKey.isEmpty
            }
        )
        XCTAssertEqual(SupportRefreshSection.inbox.responseKey, "conversations")
        XCTAssertEqual(SupportRefreshSection.knowledge.responseKey, "knowledge")
        XCTAssertEqual(
            SupportRefreshSection.announcements.responseKey,
            "announcements"
        )
    }

    func testDelayedSignOutCannotClearNewSession() async {
        let client = BackendClient()
        let old = session(accessToken: "old")
        let new = session(accessToken: "new")

        await client.setSession(old)
        await client.setSession(new)
        await client.clearSession(ifAccessTokenMatches: old.accessToken)

        let current = await client.currentSession()
        XCTAssertEqual(current?.accessToken, new.accessToken)
    }

    func testQuickAccessIsRoleAwareUniqueAndLimitedToFive() {
        let input: [PortalOperation] = [
            .weekendAttendance,
            .weekendAttendance,
            .coachAttendance,
            .weekdayAttendance,
            .matchplayAttendance,
            .oneToOneTraining,
            .myAttendance,
            .settings,
            .chats
        ]

        let superuser = QuickAccessPreferences.normalized(input, for: .superuser)
        XCTAssertEqual(superuser.count, 5)
        XCTAssertEqual(Set(superuser).count, superuser.count)

        let member = QuickAccessPreferences.normalized(input, for: .member)
        XCTAssertEqual(
            member,
            [.weekendAttendance, .myAttendance, .settings]
        )
    }

    func testQuickAccessRoundTripPreservesCustomOrder() {
        let selection: [PortalOperation] = [
            .chats,
            .makeupCredits,
            .weekendDashboard
        ]
        let encoded = QuickAccessPreferences.encode(selection, for: .superuser)
        XCTAssertEqual(
            QuickAccessPreferences.decode(encoded, for: .superuser),
            selection
        )
    }

    func testEmptyQuickAccessSelectionDoesNotRestoreDefaults() {
        let encoded = QuickAccessPreferences.encode([], for: .superuser)
        XCTAssertEqual(QuickAccessPreferences.decode(encoded, for: .superuser), [])
    }

    func testResetVerificationEnvelopeDecodesRecoverySession() throws {
        let value = session(accessToken: "recovery")
        let data = try JSONEncoder().encode(ResetVerificationEnvelope(session: value))
        let decoded = try JSONDecoder().decode(ResetVerificationEnvelope.self, from: data)
        XCTAssertEqual(decoded.session.accessToken, "recovery")
        XCTAssertEqual(decoded.session.user.id, "user-1")
    }

    @MainActor
    func testActivityMessagesRemainUntilTheirMatchingOperationEnds() {
        let state = AppState()
        let first = state.beginActivity("Saving student…")
        let second = state.beginActivity("Sending Telegram message…")

        XCTAssertEqual(state.activity?.message, "Sending Telegram message…")

        state.endActivity(first)
        XCTAssertEqual(state.activity?.message, "Sending Telegram message…")

        state.endActivity(second)
        XCTAssertNil(state.activity)
    }

    @MainActor
    func testAvatarRevisionCanForceRemoteImageRefresh() {
        let state = AppState()
        let original = state.avatarRevision

        state.reloadAvatar()

        XCTAssertNotEqual(state.avatarRevision, original)
    }

    func testExpectedCancellationRecognitionDoesNotHideRealNetworkErrors() {
        XCTAssertTrue(CancellationError().isExpectedCancellation)
        XCTAssertTrue(URLError(.cancelled).isExpectedCancellation)
        XCTAssertFalse(URLError(.notConnectedToInternet).isExpectedCancellation)
        XCTAssertFalse(BackendError.message("Permission denied.").isExpectedCancellation)
    }

    @MainActor
    func testExpectedCancellationDoesNotCreateAnErrorNotice() {
        let state = AppState()

        state.show(URLError(.cancelled))

        XCTAssertNil(state.notice)

        state.show(URLError(.notConnectedToInternet))
        XCTAssertEqual(state.notice?.kind, .error)
    }

    private func session(accessToken: String) -> AuthSession {
        AuthSession(
            accessToken: accessToken,
            refreshToken: "refresh-\(accessToken)",
            expiresIn: 3_600,
            expiresAt: Date().addingTimeInterval(3_600).timeIntervalSince1970,
            tokenType: "bearer",
            user: AuthUser(
                id: "user-1",
                email: "user@example.com",
                userMetadata: nil,
                appMetadata: nil
            )
        )
    }
}
