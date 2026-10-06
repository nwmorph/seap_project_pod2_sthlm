public without sharing class NEPRiskScoringService {

    private static final String UNMATCHED_CONFIG_KEY = 'UNMATCHED';
    private static final String QUEUE_DEVELOPER_NAME = 'Field_Response_Queue';

    public static void process(List<NEP_SensorReading__c> readings) {
        if (readings == null || readings.isEmpty()) {
            return;
        }

        // Trigger.new records are read-only in an after-trigger context, so every
        // computed field is written onto a separate per-record patch stub (Id only
        // + changed fields) rather than back onto the records the trigger handed us.
        Map<Id, NEP_SensorReading__c> patches = new Map<Id, NEP_SensorReading__c>();
        for (NEP_SensorReading__c reading : readings) {
            patches.put(reading.Id, new NEP_SensorReading__c(Id = reading.Id));
        }

        List<NEP_IntegrationLog__c> logsToInsert = new List<NEP_IntegrationLog__c>();

        Map<Id, Asset> matchedAssetByReadingId = matchTurbines(readings, patches, logsToInsert);
        Map<String, NEP_RiskThreshold_Config__mdt> configByKey = NEP_RiskThreshold_Config__mdt.getAll();

        List<NEP_SensorReading__c> escalationCandidates = new List<NEP_SensorReading__c>();
        Map<Id, Asset> escalationAssetByReadingId = new Map<Id, Asset>();

        for (NEP_SensorReading__c reading : readings) {
            NEP_SensorReading__c patch = patches.get(reading.Id);
            try {
                Asset matchedAsset = matchedAssetByReadingId.get(reading.Id);
                score(reading, matchedAsset, configByKey, patch, logsToInsert);

                if (patch.Severity__c == 'High' || patch.Severity__c == 'Critical') {
                    summarize(reading, matchedAsset, patch);
                    if (reading.Escalated__c != true) {
                        escalationCandidates.add(reading);
                        if (matchedAsset != null) {
                            escalationAssetByReadingId.put(reading.Id, matchedAsset);
                        }
                    }
                }
            } catch (Exception e) {
                logsToInsert.add(newLog(reading.Id, 'EXCEPTION', 'Scoring failed: ' + e.getMessage()));
            }
        }

        if (!escalationCandidates.isEmpty()) {
            escalate(escalationCandidates, escalationAssetByReadingId, patches, logsToInsert);
        }

        persist(patches.values(), logsToInsert);
    }

    // --- Match (INT-001) ---------------------------------------------------

    private static Map<Id, Asset> matchTurbines(
        List<NEP_SensorReading__c> readings,
        Map<Id, NEP_SensorReading__c> patches,
        List<NEP_IntegrationLog__c> logs
    ) {
        Set<String> turbineIds = new Set<String>();
        for (NEP_SensorReading__c reading : readings) {
            if (String.isNotBlank(reading.TurbineId__c)) {
                turbineIds.add(reading.TurbineId__c);
            }
        }

        Map<String, List<Asset>> assetsByExternalId = new Map<String, List<Asset>>();
        if (!turbineIds.isEmpty()) {
            List<Asset> candidateAssets = [
                SELECT Id, Name, Model__c, ExternalIdentifier
                FROM Asset
                WHERE ExternalIdentifier IN :turbineIds
                WITH USER_MODE
            ];
            for (Asset a : candidateAssets) {
                if (!assetsByExternalId.containsKey(a.ExternalIdentifier)) {
                    assetsByExternalId.put(a.ExternalIdentifier, new List<Asset>());
                }
                assetsByExternalId.get(a.ExternalIdentifier).add(a);
            }
        }

        Map<Id, Asset> matchedAssetByReadingId = new Map<Id, Asset>();
        for (NEP_SensorReading__c reading : readings) {
            NEP_SensorReading__c patch = patches.get(reading.Id);
            List<Asset> candidates = assetsByExternalId.get(reading.TurbineId__c);
            if (candidates != null && candidates.size() == 1) {
                patch.Turbine__c = candidates[0].Id;
                patch.Is_Unmatched__c = false;
                matchedAssetByReadingId.put(reading.Id, candidates[0]);
            } else {
                patch.Turbine__c = null;
                patch.Is_Unmatched__c = true;
                Boolean ambiguous = candidates != null && candidates.size() > 1;
                String detail = ambiguous
                    ? (candidates.size() + ' Assets share ExternalIdentifier = ' + reading.TurbineId__c)
                    : ('No Asset found with ExternalIdentifier = ' + reading.TurbineId__c);
                logs.add(newLog(reading.Id, ambiguous ? 'AMBIGUOUS' : 'UNMATCHED', detail));
            }
        }
        return matchedAssetByReadingId;
    }

    // --- Score (INT-003 / INT-006) ------------------------------------------

    private static void score(
        NEP_SensorReading__c reading,
        Asset matchedAsset,
        Map<String, NEP_RiskThreshold_Config__mdt> configByKey,
        NEP_SensorReading__c patch,
        List<NEP_IntegrationLog__c> logs
    ) {
        // CMDT DeveloperNames can't contain the hyphens used in the Model__c
        // picklist values, so NEP-Legacy (picklist) <-> NEP_Legacy (DeveloperName).
        String configKey = (matchedAsset != null && String.isNotBlank(matchedAsset.Model__c))
            ? matchedAsset.Model__c.replace('-', '_')
            : UNMATCHED_CONFIG_KEY;

        NEP_RiskThreshold_Config__mdt config = configByKey.get(configKey);
        if (config == null) {
            logs.add(newLog(reading.Id, 'EXCEPTION',
                'No NEP_RiskThreshold_Config__mdt row for key ' + configKey + '; applied UNMATCHED fallback thresholds.'));
            configKey = UNMATCHED_CONFIG_KEY;
            config = configByKey.get(UNMATCHED_CONFIG_KEY);
        }

        Boolean tempElevated = reading.Temperature_C__c > config.Temp_Threshold_C__c;
        Boolean vibElevated = reading.Vibration_Hz__c > config.Vibration_Threshold_Hz__c;

        String severity;
        if (tempElevated && vibElevated) {
            severity = 'Critical';
        } else if (vibElevated) {
            severity = 'High';
        } else if (tempElevated) {
            severity = 'Medium';
        } else {
            severity = 'Normal';
        }

        patch.Severity__c = severity;
        patch.Applied_Model__c = configKey;
        patch.Applied_Temp_Threshold__c = config.Temp_Threshold_C__c;
        patch.Applied_Vib_Threshold__c = config.Vibration_Threshold_Hz__c;
    }

    // --- Summarise (INT-004) ------------------------------------------------

    private static void summarize(NEP_SensorReading__c reading, Asset matchedAsset, NEP_SensorReading__c patch) {
        String context = (matchedAsset != null)
            ? matchedAsset.Name
            : ('Turbine ' + reading.TurbineId__c + ' (unmatched)');
        String modelLabel = String.isNotBlank(patch.Applied_Model__c)
            ? patch.Applied_Model__c.replace('_', '-')
            : UNMATCHED_CONFIG_KEY;

        Boolean tempElevated = reading.Temperature_C__c > patch.Applied_Temp_Threshold__c;
        Boolean vibElevated = reading.Vibration_Hz__c > patch.Applied_Vib_Threshold__c;

        String condition = (tempElevated && vibElevated)
            ? 'elevated temperature and elevated vibration'
            : (vibElevated ? 'elevated vibration' : 'elevated temperature');

        patch.Plain_Language_Summary__c = context + ' is showing ' + condition
            + ' against its ' + modelLabel + ' thresholds and is flagged ' + patch.Severity__c + '.';
    }

    // --- Escalate (INT-005) --------------------------------------------------

    private static void escalate(
        List<NEP_SensorReading__c> candidates,
        Map<Id, Asset> assetByReadingId,
        Map<Id, NEP_SensorReading__c> patches,
        List<NEP_IntegrationLog__c> logs
    ) {
        Id queueId = resolveFieldResponseQueueId();
        if (queueId == null) {
            for (NEP_SensorReading__c reading : candidates) {
                logs.add(newLog(reading.Id, 'EXCEPTION', 'Field Response Queue not found; Case not created.'));
            }
            return;
        }

        List<Case> casesToInsert = new List<Case>();
        List<NEP_SensorReading__c> readingByCaseIndex = new List<NEP_SensorReading__c>();

        for (NEP_SensorReading__c reading : candidates) {
            NEP_SensorReading__c patch = patches.get(reading.Id);
            Asset matchedAsset = assetByReadingId.get(reading.Id);
            String turbineLabel = (matchedAsset != null) ? matchedAsset.Name : ('Turbine ' + reading.TurbineId__c);

            casesToInsert.add(new Case(
                OwnerId = queueId,
                Subject = patch.Severity__c + ' alert — ' + turbineLabel,
                Description = patch.Plain_Language_Summary__c,
                Priority = (patch.Severity__c == 'Critical') ? 'High' : 'Medium',
                NEP_Severity__c = patch.Severity__c,
                NEP_Alert_Summary__c = patch.Plain_Language_Summary__c,
                NEP_SensorReading__c = reading.Id,
                NEP_Turbine__c = (matchedAsset != null) ? matchedAsset.Id : null,
                NEP_Unmatched__c = patch.Is_Unmatched__c
            ));
            readingByCaseIndex.add(reading);
        }

        List<Database.SaveResult> results = Database.insert(casesToInsert, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < results.size(); i++) {
            NEP_SensorReading__c reading = readingByCaseIndex[i];
            if (results[i].isSuccess()) {
                patches.get(reading.Id).Escalated__c = true;
            } else {
                logs.add(newLog(reading.Id, 'EXCEPTION', 'Case creation failed: ' + results[i].getErrors()[0].getMessage()));
            }
        }
    }

    private static Id resolveFieldResponseQueueId() {
        List<Group> queues = [
            SELECT Id FROM Group
            WHERE Type = 'Queue' AND DeveloperName = :QUEUE_DEVELOPER_NAME
            WITH USER_MODE
            LIMIT 1
        ];
        return queues.isEmpty() ? null : queues[0].Id;
    }

    // --- Persistence (INT-007) -----------------------------------------------

    private static void persist(List<NEP_SensorReading__c> patches, List<NEP_IntegrationLog__c> logs) {
        List<Database.SaveResult> updateResults = Database.update(patches, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < updateResults.size(); i++) {
            if (!updateResults[i].isSuccess()) {
                logs.add(newLog(patches[i].Id, 'EXCEPTION', 'Reading update failed: ' + updateResults[i].getErrors()[0].getMessage()));
            }
        }

        if (!logs.isEmpty()) {
            Database.insert(logs, false, AccessLevel.USER_MODE);
        }
    }

    private static NEP_IntegrationLog__c newLog(Id readingId, String reason, String detail) {
        return new NEP_IntegrationLog__c(
            Reading__c = readingId,
            Reason__c = reason,
            Detail__c = detail,
            Logged_At__c = Datetime.now()
        );
    }
}
