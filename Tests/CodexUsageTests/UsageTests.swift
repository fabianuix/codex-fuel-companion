import Foundation

func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "Expected \(b), got \(a)") }
func XCTAssertTrue(_ value: Bool) { precondition(value) }
func XCTAssertFalse(_ value: Bool) { precondition(!value) }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
func XCTUnwrap<T>(_ value: T?) throws -> T { guard let value else { throw NSError(domain: "Test", code: 1) }; return value }

@main struct UsageTests {
    static func main() throws {
        let suite = UsageTests()
        suite.testQuotaClampsAndNamesByDuration()
        suite.testMissingCreditsAreNotZeroAndUnitsAreNotCurrency()
        try suite.testMultiBucketPreferredAndShortWindowSortsFirst()
        try suite.testLegacyAndNullDataDecode()
        try suite.testReadOnlyProtocolAndPartialFailure()
        try suite.testReasoningReadOnlyProtocol()
        try suite.testReasoningMetadataAvailability()
        try suite.testStalledServerTimesOut()
        try suite.testCreditPrimarySwitch()
        try suite.testResetProtocolAndRetryKeys()
        try suite.testPlanAdaptiveWindows()
        print("PASS: 3 model checks, read-only connection check, timeout check")
    }
    func testQuotaClampsAndNamesByDuration() {
        XCTAssertEqual(LimitWindow(usedPercent: 120, windowDurationMins: 10080, resetsAt: nil).remaining, 0)
        XCTAssertEqual(LimitWindow(usedPercent: -5, windowDurationMins: 300, resetsAt: nil).remaining, 100)
        XCTAssertEqual(LimitWindow(usedPercent: 45, windowDurationMins: 10080, resetsAt: nil).title, "Weekly limit")
        XCTAssertEqual(LimitWindow(usedPercent: 45, windowDurationMins: 300, resetsAt: nil).title, "5-hour limit")
    }
    func testMissingCreditsAreNotZeroAndUnitsAreNotCurrency() {
        XCTAssertEqual(Credits(hasCredits: true, unlimited: false, balance: nil).display, "Available")
        XCTAssertEqual(Credits(hasCredits: false, unlimited: false, balance: nil).display, "No credits")
        XCTAssertEqual(Credits(hasCredits: true, unlimited: true, balance: nil).display, "Unlimited")
        let display = Credits(hasCredits: true, unlimited: false, balance: "103.0894870000").display
        XCTAssertTrue(display.contains("103"))
        XCTAssertFalse(display.contains("RON"))
    }
    func testMultiBucketPreferredAndShortWindowSortsFirst() throws {
        let json = """
        {"rateLimits":{"limitId":"codex","primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":300},"secondary":{"usedPercent":70,"windowDurationMins":10080}},"spark":{"limitId":"spark","limitName":"Spark"}}}
        """
        let result = try JSONDecoder().decode(LimitsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(result.main.windows.first?.remaining, 80)
        XCTAssertEqual(result.main.limitingWindow?.remaining, 30)
        XCTAssertEqual(result.otherBuckets.count, 1)
        XCTAssertNil(result.main.credits)
    }
    func testLegacyAndNullDataDecode() throws {
        let result = try JSONDecoder().decode(LimitsResponse.self, from: Data("{\"rateLimits\":{\"primary\":null,\"credits\":null}}".utf8))
        XCTAssertTrue(result.main.windows.isEmpty)
        XCTAssertTrue(result.otherBuckets.isEmpty)
    }
    func fakeServer(_ code: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("codex-usage-test-" + UUID().uuidString)
        try ("#!/usr/bin/python3\n" + code).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
    func testReadOnlyProtocolAndPartialFailure() throws {
        let server = try fakeServer("""
        import sys,json
        def read(): return json.loads(sys.stdin.readline())
        def send(o): print(json.dumps(o),flush=True)
        assert read()['method']=='initialize'
        send({'id':1,'result':{}})
        assert read()['method']=='initialized'
        assert read()['method']=='account/rateLimits/read'
        send({'id':2,'result':{'rateLimits':{'primary':{'usedPercent':40,'windowDurationMins':10080}}}})
        sys.stdin.read()
        """)
        defer { try? FileManager.default.removeItem(at: server) }
        let result = try CodexClient.fetch(binary: server, timeoutSeconds: 3)
        XCTAssertEqual(result.limits?.main.windows.first?.remaining, 60)
        XCTAssertNil(result.limitsError)
    }
    func reasoningServer(resultJSON: String) throws -> URL {
        let encodedResult = Data(resultJSON.utf8).base64EncodedString()
        return try fakeServer("""
        import sys,json,base64
        def read(): return json.loads(sys.stdin.readline())
        def send(o): print(json.dumps(o),flush=True)
        initialization=read()
        assert initialization['method']=='initialize'
        assert initialization['params']['capabilities']['experimentalApi'] is True
        send({'id':1,'result':{}})
        assert read()['method']=='initialized'
        request=read()
        assert request['method']=='thread/list'
        assert request['params']=={
            'limit':1,
            'sortKey':'recency_at',
            'sortDirection':'desc',
            'sourceKinds':['cli','vscode','appServer'],
            'useStateDbOnly':True,
            'archived':False
        }
        send({'id':request['id'],'result':json.loads(base64.b64decode('\(encodedResult)'))})
        sys.stdin.read()
        """)
    }
    func testReasoningReadOnlyProtocol() throws {
        let server = try reasoningServer(resultJSON: #"{"data":[{"id":"latest-task","model":"gpt-6-astra","reasoningEffort":"ultra","status":{"type":"notLoaded"},"preview":"Ignored metadata","turns":[]}],"nextCursor":null}"#)
        defer { try? FileManager.default.removeItem(at: server) }
        XCTAssertEqual(try CodexClient.fetchReasoning(binary: server, timeoutSeconds: 3), .ultra)
        print("PASS: read-only latest-task reasoning request, source filters, and persisted Ultra effort")
    }
    func testReasoningMetadataAvailability() throws {
        for raw in ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"] {
            let server = try reasoningServer(resultJSON: "{\"data\":[{\"reasoningEffort\":\"\(raw)\"}]}")
            defer { try? FileManager.default.removeItem(at: server) }
            XCTAssertEqual(try CodexClient.fetchReasoning(binary: server, timeoutSeconds: 3)?.rawValue, raw)
        }
        for result in [
            #"{"data":[]}"#,
            #"{"data":[{}]}"#,
            #"{"data":[{"reasoningEffort":null}]}"#,
            #"{"data":[{"reasoningEffort":""}]}"#,
            #"{"data":[{"reasoningEffort":"future_effort"}]}"#
        ] {
            let server = try reasoningServer(resultJSON: result)
            defer { try? FileManager.default.removeItem(at: server) }
            XCTAssertNil(try CodexClient.fetchReasoning(binary: server, timeoutSeconds: 3))
        }
        print("PASS: all eight reasoning efforts, no tasks, missing or null effort, and unknown future values")
    }
    func testStalledServerTimesOut() throws {
        let server = try fakeServer("import time\ntime.sleep(60)\n")
        defer { try? FileManager.default.removeItem(at: server) }
        let start = Date()
        let result = try CodexClient.fetch(binary: server, timeoutSeconds: 0.25)
        XCTAssertTrue(Date().timeIntervalSince(start) < 3)
        XCTAssertNil(result.limits)
        XCTAssertTrue(result.limitsError != nil)
    }
    func testCreditPrimarySwitch() throws {
        func bucket(used: Int, balance: String?, hasCredits: Bool = true, duration: Int = 10080) throws -> LimitBucket {
            let data = try JSONSerialization.data(withJSONObject: ["primary": ["usedPercent": used, "windowDurationMins": duration], "credits": ["hasCredits": hasCredits, "unlimited": false, "balance": balance as Any? ?? NSNull()]])
            return try JSONDecoder().decode(LimitBucket.self, from: data)
        }
        let creditMode = try bucket(used: 100, balance: "1234.5")
        XCTAssertTrue(creditMode.usesCredits)
        XCTAssertTrue(creditMode.primaryMenuValue.hasSuffix(" cr"))
        let weeklyMode = try bucket(used: 80, balance: "1234.5")
        XCTAssertFalse(weeklyMode.usesCredits)
        XCTAssertEqual(weeklyMode.primaryMenuValue, "20%")
        XCTAssertFalse(try bucket(used: 100, balance: "0").usesCredits)
        XCTAssertFalse(try bucket(used: 100, balance: "100", hasCredits: false).usesCredits)
        XCTAssertTrue(try bucket(used: 100, balance: "100", duration: 300).usesCredits)
        XCTAssertTrue(try bucket(used: 100, balance: nil).usesCredits)
        print("PASS: credits switch, depleted balance, unknown balance, and weekly reset")
    }
    func testPlanAdaptiveWindows() throws {
        for plan in ["free", "go", "plus", "pro", "prolite", "business", "team", "enterprise", "edu", "future_plan"] {
            for durations in [[300, 10080], [10080], [300], [60], []] {
                var bucket: [String: Any] = ["planType": plan]
                for (index, duration) in durations.enumerated() {
                    bucket[index == 0 ? "primary" : "secondary"] = ["usedPercent": index == 0 ? 85 : 25, "windowDurationMins": duration]
                }
                let data = try JSONSerialization.data(withJSONObject: ["rateLimits": bucket])
                let limits = try JSONDecoder().decode(LimitsResponse.self, from: data)
                XCTAssertEqual(limits.main.windows.count, durations.count)
                XCTAssertEqual(limits.main.windows.compactMap(\.windowDurationMins), durations.sorted())
                XCTAssertEqual(limits.main.primaryMenuValue, durations.isEmpty ? "—" : "15%")
                XCTAssertTrue(limits.planName != nil)
                XCTAssertNil(limits.main.credits)
                XCTAssertNil(limits.rateLimitResetCredits)
            }
        }
        let data = Data(#"{"rateLimits":{"planType":"plus"},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":100,"windowDurationMins":300},"secondary":{"usedPercent":20,"windowDurationMins":10080},"credits":{"hasCredits":true,"unlimited":false,"balance":"50"}}}}"#.utf8)
        let limits = try JSONDecoder().decode(LimitsResponse.self, from: data)
        XCTAssertEqual(limits.planName, "Plus")
        XCTAssertTrue(limits.main.usesCredits)
        XCTAssertEqual(limits.main.limitingWindow?.windowDurationMins, 300)
        let creditOnly = LimitBucket(limitId: "codex", limitName: nil, primary: nil, secondary: nil, credits: Credits(hasCredits: true, unlimited: false, balance: "500"), planType: "business")
        XCTAssertTrue(creditOnly.usesCredits)
        XCTAssertTrue(creditOnly.primaryMenuValue.hasSuffix(" cr"))
        print("PASS: 50 plan/window combinations, plan fallback, five-hour exhaustion, and credits-only accounts")
    }
    func testResetProtocolAndRetryKeys() throws {
        var book = ResetRequestBook()
        let key = book.begin(for: "accountA")
        XCTAssertEqual(book.begin(for: "accountA"), key)
        XCTAssertFalse(book.begin(for: "accountB") == key)
        var restored = try JSONDecoder().decode(ResetRequestBook.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(restored.begin(for: "accountA"), key)
        restored.complete(for: "accountA")
        XCTAssertFalse(restored.begin(for: "accountA") == key)
        for outcome in ["reset", "alreadyRedeemed", "nothingToReset", "noCredit"] {
            let server = try fakeServer("""
            import sys,json
            def read(): return json.loads(sys.stdin.readline())
            def send(o): print(json.dumps(o),flush=True)
            assert read()['method']=='initialize'
            send({'id':1,'result':{}})
            assert read()['method']=='initialized'
            request=read()
            assert request['method']=='account/rateLimitResetCredit/consume'
            assert request['params']=={'idempotencyKey':'\(key)'}
            send({'id':2,'result':{'outcome':'\(outcome)'}})
            sys.stdin.read()
            """)
            defer { try? FileManager.default.removeItem(at: server) }
            let result = try CodexClient.consumeReset(idempotencyKey: key, binary: server, timeoutSeconds: 3)
            XCTAssertEqual(result.rawValue, outcome)
        }
        let credits = Credits(hasCredits: true, unlimited: false, balance: "1234.99")
        XCTAssertEqual(credits.display, 1234.0.formatted(.number.precision(.fractionLength(0))))
        print("PASS: four reset outcomes, persistent retry keys, account isolation, and whole credits")
    }
}
