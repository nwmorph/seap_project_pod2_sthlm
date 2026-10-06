public without sharing class NEPSensorReadingTriggerHandler {

    // Transaction-scoped recursion guard: NEPRiskScoringService.process() updates the
    // same records it is given, which re-fires this after-update trigger. Without this
    // guard that update would recurse into process() forever.
    @TestVisible
    private static Boolean hasRun = false;

    public static void afterInsert(List<NEP_SensorReading__c> newReadings) {
        run(newReadings);
    }

    public static void afterUpdate(List<NEP_SensorReading__c> newReadings) {
        run(newReadings);
    }

    private static void run(List<NEP_SensorReading__c> readings) {
        if (hasRun) {
            return;
        }
        hasRun = true;
        NEPRiskScoringService.process(readings);
    }
}
