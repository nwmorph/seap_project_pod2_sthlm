@isTest
private class NEPRiskScoringServiceTest {

    // --- Fixture helpers -----------------------------------------------------

    @testSetup
    static void setup() {
        insert new Account(Name = 'NEP Test Fleet Owner');
    }

    private static Id testAccountId;

    private static Id getTestAccountId() {
        if (testAccountId == null) {
            testAccountId = [SELECT Id FROM Account LIMIT 1].Id;
        }
        return testAccountId;
    }

    // This org enforces "every Asset needs an Account, a Contact, or both" via a
    // validation rule not visible on the standard field describe, so every test
    // Asset must carry an AccountId.
    private static Asset makeAsset(String name, String model, String externalId) {
        return new Asset(Name = name, Model__c = model, ExternalIdentifier = externalId, AccountId = getTestAccountId());
    }

    private static NEP_SensorReading__c makeReading(String externalId, String turbineId, Decimal temp, Decimal vib) {
        return new NEP_SensorReading__c(
            External_Id__c = externalId,
            TurbineId__c = turbineId,
            Temperature_C__c = temp,
            Vibration_Hz__c = vib,
            Reading_Timestamp__c = Datetime.now()
        );
    }

    private static Id fieldResponseQueueId() {
        return [SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'Field_Response_Queue' LIMIT 1].Id;
    }

    // --- Match (SC-INT-001) ----------------------------------------------------

    @isTest
    static void testSingleMatch_setsTurbineAndClearsUnmatched() {
        Asset turbine = makeAsset('Vestervind 1', 'NEP-Legacy', 'TURB-001');
        insert turbine;

        NEP_SensorReading__c reading = makeReading('EXT-001', 'TURB-001', 10, 10);
        insert reading;

        NEP_SensorReading__c result = [SELECT Turbine__c, Is_Unmatched__c FROM NEP_SensorReading__c WHERE Id = :reading.Id];
        System.assertEquals(turbine.Id, result.Turbine__c, 'Exactly one match must set Turbine__c');
        System.assertEquals(false, result.Is_Unmatched__c, 'A matched reading must not be flagged unmatched');
    }

    @isTest
    static void testNoMatch_marksUnmatchedAndLogsReason() {
        NEP_SensorReading__c reading = makeReading('EXT-002', 'TURB-NONE', 10, 10);
        insert reading;

        NEP_SensorReading__c result = [SELECT Turbine__c, Is_Unmatched__c FROM NEP_SensorReading__c WHERE Id = :reading.Id];
        System.assertEquals(null, result.Turbine__c, 'No match must leave Turbine__c null');
        System.assertEquals(true, result.Is_Unmatched__c, 'No match must flag the reading unmatched');

        List<NEP_IntegrationLog__c> logs = [SELECT Reason__c FROM NEP_IntegrationLog__c WHERE Reading__c = :reading.Id];
        System.assertEquals(1, logs.size(), 'Exactly one log entry must be written for a no-match reading');
        System.assertEquals('UNMATCHED', logs[0].Reason__c);
    }

    @isTest
    static void testAmbiguousMatch_marksUnmatchedAndLogsAmbiguous() {
        insert new List<Asset>{
            makeAsset('Duplicate A', 'NEP-Legacy', 'TURB-DUP'),
            makeAsset('Duplicate B', 'NEP-Standard', 'TURB-DUP')
        };

        NEP_SensorReading__c reading = makeReading('EXT-003', 'TURB-DUP', 10, 10);
        insert reading;

        NEP_SensorReading__c result = [SELECT Turbine__c, Is_Unmatched__c FROM NEP_SensorReading__c WHERE Id = :reading.Id];
        System.assertEquals(null, result.Turbine__c, 'An ambiguous match must leave Turbine__c null');
        System.assertEquals(true, result.Is_Unmatched__c);

        List<NEP_IntegrationLog__c> logs = [SELECT Reason__c FROM NEP_IntegrationLog__c WHERE Reading__c = :reading.Id];
        System.assertEquals(1, logs.size());
        System.assertEquals('AMBIGUOUS', logs[0].Reason__c);
    }

    @isTest
    static void testProcessing_neverDeletesReadings() {
        insert makeAsset('Vestervind 2', 'NEP-Legacy', 'TURB-004');
        insert new List<NEP_SensorReading__c>{
            makeReading('EXT-004', 'TURB-004', 95, 60),
            makeReading('EXT-005', 'TURB-NONE', 10, 10)
        };

        Integer count = [SELECT COUNT() FROM NEP_SensorReading__c];
        System.assertEquals(2, count, 'Matched and unmatched readings must both be retained, never deleted');
    }

    // --- Score (SC-INT-003) -----------------------------------------------------

    @isTest
    static void testScore_legacyVsStandardDifferential_sameRawValues() {
        insert new List<Asset>{
            makeAsset('Legacy Turbine', 'NEP-Legacy', 'TURB-LEG'),
            makeAsset('Standard Turbine', 'NEP-Standard', 'TURB-STD')
        };

        // 85 / 48: above Legacy's 80 vib threshold? No - exercise differential at temp=85 (between Legacy 90 and Standard 80).
        insert new List<NEP_SensorReading__c>{
            makeReading('EXT-010', 'TURB-LEG', 85, 10),
            makeReading('EXT-011', 'TURB-STD', 85, 10)
        };

        Map<String, String> severityByExternalId = new Map<String, String>();
        for (NEP_SensorReading__c r : [SELECT External_Id__c, Severity__c FROM NEP_SensorReading__c]) {
            severityByExternalId.put(r.External_Id__c, r.Severity__c);
        }

        System.assertEquals('Normal', severityByExternalId.get('EXT-010'), 'Legacy threshold (90) is not exceeded at 85');
        System.assertEquals('Medium', severityByExternalId.get('EXT-011'), 'Standard threshold (80) is exceeded at 85');
    }

    @isTest
    static void testScore_criticalAndNormalBoundaries() {
        insert makeAsset('Legacy Turbine', 'NEP-Legacy', 'TURB-LEG2');

        insert new List<NEP_SensorReading__c>{
            makeReading('EXT-020', 'TURB-LEG2', 95, 50), // both elevated -> Critical
            makeReading('EXT-021', 'TURB-LEG2', 10, 10)   // neither elevated -> Normal
        };

        Map<String, String> severityByExternalId = new Map<String, String>();
        for (NEP_SensorReading__c r : [SELECT External_Id__c, Severity__c FROM NEP_SensorReading__c]) {
            severityByExternalId.put(r.External_Id__c, r.Severity__c);
        }

        System.assertEquals('Critical', severityByExternalId.get('EXT-020'));
        System.assertEquals('Normal', severityByExternalId.get('EXT-021'));
    }

    @isTest
    static void testScore_unmatchedUsesFallbackThresholds() {
        // UNMATCHED fallback is seeded at 90 / 45 (same as NEP-Legacy).
        insert makeReading('EXT-030', 'TURB-UNKNOWN', 95, 50);

        NEP_SensorReading__c result = [
            SELECT Severity__c, Applied_Model__c, Applied_Temp_Threshold__c, Applied_Vib_Threshold__c
            FROM NEP_SensorReading__c WHERE External_Id__c = 'EXT-030'
        ];
        System.assertEquals('Critical', result.Severity__c);
        System.assertEquals('UNMATCHED', result.Applied_Model__c);
        System.assertEquals(90, result.Applied_Temp_Threshold__c);
        System.assertEquals(45, result.Applied_Vib_Threshold__c);
    }

    @isTest
    static void testScore_strictlyGreaterThan_valueAtExactThresholdIsNotElevated() {
        insert makeAsset('Standard Turbine', 'NEP-Standard', 'TURB-STD2');

        // Standard thresholds are exactly 80 / 50 - values equal to threshold must NOT be elevated.
        insert makeReading('EXT-040', 'TURB-STD2', 80, 50);

        NEP_SensorReading__c result = [SELECT Severity__c FROM NEP_SensorReading__c WHERE External_Id__c = 'EXT-040'];
        System.assertEquals('Normal', result.Severity__c, 'A value exactly at the threshold must not count as elevated');
    }

    // --- Summarise (SC-INT-004) --------------------------------------------------

    @isTest
    static void testSummary_criticalNamesBothElevatedConditions() {
        insert makeAsset('Legacy Turbine', 'NEP-Legacy', 'TURB-LEG3');
        insert makeReading('EXT-050', 'TURB-LEG3', 95, 50);

        NEP_SensorReading__c result = [SELECT Plain_Language_Summary__c FROM NEP_SensorReading__c WHERE External_Id__c = 'EXT-050'];
        System.assert(result.Plain_Language_Summary__c.contains('elevated temperature'), 'Critical summary must name elevated temperature');
        System.assert(result.Plain_Language_Summary__c.contains('elevated vibration'), 'Critical summary must name elevated vibration');
    }

    @isTest
    static void testSummary_highNamesVibrationOnly() {
        insert makeAsset('Legacy Turbine', 'NEP-Legacy', 'TURB-LEG4');
        insert makeReading('EXT-051', 'TURB-LEG4', 10, 50); // vib elevated only -> High

        NEP_SensorReading__c result = [SELECT Severity__c, Plain_Language_Summary__c FROM NEP_SensorReading__c WHERE External_Id__c = 'EXT-051'];
        System.assertEquals('High', result.Severity__c);
        System.assert(result.Plain_Language_Summary__c.contains('elevated vibration'));
        System.assert(!result.Plain_Language_Summary__c.contains('elevated temperature'), 'High-via-vibration summary must not claim temperature is elevated');
    }

    @isTest
    static void testSummary_noneForNormalOrMedium() {
        insert makeAsset('Legacy Turbine', 'NEP-Legacy', 'TURB-LEG5');
        insert new List<NEP_SensorReading__c>{
            makeReading('EXT-052', 'TURB-LEG5', 10, 10), // Normal
            makeReading('EXT-053', 'TURB-LEG5', 95, 10)  // temp only -> Medium
        };

        for (NEP_SensorReading__c r : [SELECT Severity__c, Plain_Language_Summary__c FROM NEP_SensorReading__c]) {
            System.assert(r.Severity__c == 'Normal' || r.Severity__c == 'Medium');
            System.assertEquals(null, r.Plain_Language_Summary__c, 'Normal/Medium readings must carry no summary');
        }
    }

    @isTest
    static void testSummary_deterministicOnReprocess() {
        insert makeAsset('Legacy Turbine', 'NEP-Legacy', 'TURB-LEG6');
        insert makeReading('EXT-054', 'TURB-LEG6', 95, 50);

        NEP_SensorReading__c first = [
            SELECT Id, TurbineId__c, Temperature_C__c, Vibration_Hz__c, Escalated__c, Plain_Language_Summary__c
            FROM NEP_SensorReading__c WHERE External_Id__c = 'EXT-054'
        ];
        String firstSummary = first.Plain_Language_Summary__c;

        // Reprocess directly against the service (bypasses the trigger's transaction-scoped recursion guard).
        NEPRiskScoringService.process(new List<NEP_SensorReading__c>{ first });

        NEP_SensorReading__c second = [SELECT Plain_Language_Summary__c FROM NEP_SensorReading__c WHERE Id = :first.Id];
        System.assertEquals(firstSummary, second.Plain_Language_Summary__c, 'Reprocessing must yield a byte-identical summary');
    }

    // --- Escalate (SC-INT-005) ----------------------------------------------------

    @isTest
    static void testEscalate_highAndCriticalBothCreateACase() {
        insert makeAsset('Legacy Turbine', 'NEP-Legacy', 'TURB-LEG7');
        insert new List<NEP_SensorReading__c>{
            makeReading('EXT-060', 'TURB-LEG7', 95, 50), // Critical
            makeReading('EXT-061', 'TURB-LEG7', 10, 50)  // High
        };

        Id queueId = fieldResponseQueueId();
        List<Case> cases = [SELECT NEP_Severity__c, OwnerId FROM Case WHERE NEP_SensorReading__r.External_Id__c IN ('EXT-060', 'EXT-061')];
        System.assertEquals(2, cases.size(), 'Both High and Critical readings must escalate');
        for (Case c : cases) {
            System.assertEquals(queueId, c.OwnerId, 'Escalation Cases must be owned by the Field Response Queue');
        }
    }

    @isTest
    static void testEscalate_unmatchedSourcedCaseIsFlagged() {
        insert makeReading('EXT-070', 'TURB-UNKNOWN2', 95, 50); // Critical via UNMATCHED fallback

        Case c = [SELECT NEP_Unmatched__c, NEP_Turbine__c FROM Case WHERE NEP_SensorReading__r.External_Id__c = 'EXT-070'];
        System.assertEquals(true, c.NEP_Unmatched__c);
        System.assertEquals(null, c.NEP_Turbine__c);
    }

    @isTest
    static void testEscalate_noCaseForNormalOrMedium() {
        insert makeAsset('Legacy Turbine', 'NEP-Legacy', 'TURB-LEG8');
        insert new List<NEP_SensorReading__c>{
            makeReading('EXT-080', 'TURB-LEG8', 10, 10), // Normal
            makeReading('EXT-081', 'TURB-LEG8', 95, 10)  // Medium
        };

        Integer caseCount = [SELECT COUNT() FROM Case WHERE NEP_SensorReading__r.External_Id__c IN ('EXT-080', 'EXT-081')];
        System.assertEquals(0, caseCount, 'Normal/Medium readings must never escalate');
    }

    @isTest
    static void testEscalate_noSecondCaseOnReprocess() {
        insert makeAsset('Legacy Turbine', 'NEP-Legacy', 'TURB-LEG9');
        insert makeReading('EXT-090', 'TURB-LEG9', 95, 50); // Critical, escalates once

        NEP_SensorReading__c reading = [
            SELECT Id, TurbineId__c, Temperature_C__c, Vibration_Hz__c, Escalated__c
            FROM NEP_SensorReading__c WHERE External_Id__c = 'EXT-090'
        ];
        System.assertEquals(true, reading.Escalated__c);

        NEPRiskScoringService.process(new List<NEP_SensorReading__c>{ reading });

        Integer caseCount = [SELECT COUNT() FROM Case WHERE NEP_SensorReading__c = :reading.Id];
        System.assertEquals(1, caseCount, 'Reprocessing an already-escalated reading must not create a second Case');
    }

    // --- Bulk & idempotency (SC-INT-007) ------------------------------------------

    @isTest
    static void testBulkBatch_noGovernorLimitFailure() {
        List<Asset> turbines = new List<Asset>();
        for (Integer i = 0; i < 200; i++) {
            turbines.add(makeAsset('Bulk Turbine ' + i, 'NEP-Standard', 'TURB-BULK-' + i));
        }
        insert turbines;

        List<NEP_SensorReading__c> readings = new List<NEP_SensorReading__c>();
        for (Integer i = 0; i < 200; i++) {
            Integer bucket = Math.mod(i, 4);
            Decimal temp = (bucket == 0 || bucket == 2) ? 85 : 10; // temp elevated for bucket 0 (Critical) and 2 (Medium)
            Decimal vib = (bucket == 0 || bucket == 1) ? 55 : 10;  // vib elevated for bucket 0 (Critical) and 1 (High)
            readings.add(makeReading('EXT-BULK-' + i, 'TURB-BULK-' + i, temp, vib));
        }

        Test.startTest();
        insert readings;
        Test.stopTest();

        Integer scoredCount = [SELECT COUNT() FROM NEP_SensorReading__c WHERE Severity__c != null];
        System.assertEquals(200, scoredCount, 'Every reading in the batch must receive a severity');

        Integer caseCount = [SELECT COUNT() FROM Case WHERE NEP_SensorReading__c != null];
        System.assertEquals(100, caseCount, 'Buckets 0 (Critical) and 1 (High) are 50 + 50 readings and must each escalate exactly once');
    }

    @isTest
    static void testPartialFailure_isolatedToTheFailingRecord() {
        insert new List<NEP_SensorReading__c>{
            makeReading('EXT-100', 'TURB-UNKNOWN3', 10, 10),
            makeReading('EXT-101', 'TURB-UNKNOWN4', 10, 10),
            makeReading('EXT-102', 'TURB-UNKNOWN5', 10, 10)
        };

        List<NEP_SensorReading__c> readings = [SELECT Id, TurbineId__c, Temperature_C__c, Vibration_Hz__c, Escalated__c
                                                FROM NEP_SensorReading__c ORDER BY External_Id__c];
        Id survivingId1 = readings[0].Id;
        Id doomedId = readings[1].Id;
        Id survivingId2 = readings[2].Id;

        delete new NEP_SensorReading__c(Id = doomedId);

        // Reprocess the stale list directly against the service - the deleted record's
        // own update (and even its own EXCEPTION log, since that log's lookup would
        // point at the now-nonexistent row) cannot succeed, but the other two records
        // in the same allOrNone=false batch must still be isolated from that failure
        // and persist correctly. No exception should propagate out of process().
        NEPRiskScoringService.process(readings);

        List<NEP_SensorReading__c> survivors = [
            SELECT Severity__c FROM NEP_SensorReading__c WHERE Id IN (:survivingId1, :survivingId2)
        ];
        System.assertEquals(2, survivors.size());
        for (NEP_SensorReading__c survivor : survivors) {
            System.assertEquals('Normal', survivor.Severity__c, 'Surviving records in the same batch must still be persisted');
        }
    }

    @isTest
    static void testProcess_emptyAndNullListsAreNoOps() {
        Test.startTest();
        NEPRiskScoringService.process(new List<NEP_SensorReading__c>());
        NEPRiskScoringService.process(null);
        Test.stopTest();
        // No exception thrown is the assertion.
    }
}
