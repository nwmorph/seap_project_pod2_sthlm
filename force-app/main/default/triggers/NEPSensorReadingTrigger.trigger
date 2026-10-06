trigger NEPSensorReadingTrigger on NEP_SensorReading__c (after insert, after update) {
    if (Trigger.isInsert) {
        NEPSensorReadingTriggerHandler.afterInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
        NEPSensorReadingTriggerHandler.afterUpdate(Trigger.new);
    }
}
