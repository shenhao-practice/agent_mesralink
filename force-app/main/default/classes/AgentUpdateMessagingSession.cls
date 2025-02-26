/*
Invocable Apex by Agentforce to update MessagingSession fields
Input is MessagingSession Record and Function Name
Created by: Hao Shen (SFDC)
Created date: 2025-02-03
Modified date: 2025-02-12
*/
public without sharing class AgentUpdateMessagingSession {
    
    // Wrapper class to hold input parameters
    public class FlowInput {
        @InvocableVariable(required=true)
        public Id messagingSessionId;
        
        @InvocableVariable(required=true)
        public String functionName;
    }

    public class FlowOutput {
        @InvocableVariable(required=false)
        public Boolean status;
    }
    
    // Main invocable method that routes to specific functions
    @InvocableMethod(label='Agent Update Messaging Session')
    public static List<FlowOutput> processMessagingSession(List<FlowInput> inputs) {
        List<FlowOutput> outputs = new List<FlowOutput>();
        FlowOutput output = new FlowOutput();
        output.status = false;

        // Ensure the input list is not empty
        if (inputs == null || inputs.isEmpty()) {
            outputs.add(output);
            return outputs;
        }
        
        // Create lists to hold IDs for each function
        List<Id> escalateIds = new List<Id>();
        List<Id> handleIds = new List<Id>();
        
        // Sort IDs based on function name
        for (FlowInput input : inputs) {
            if (input.functionName == 'Escalated by Agentforce') {
                escalateIds.add(input.messagingSessionId);
            } else if (input.functionName == 'Handled by Agentforce') {
                handleIds.add(input.messagingSessionId);
            }
        }
        
        // Execute appropriate functions
        if (!escalateIds.isEmpty()) {
            output.status = updateEscalation(escalateIds);
        }
        if (!handleIds.isEmpty()) {
            output.status = updateHandled(handleIds);
        }

        outputs.add(output);
        return outputs;
    }
    
    // Method to update Escalated_by_Agentforce__c
    private static Boolean updateEscalation(List<Id> messagingSessionIds) {
        List<MessagingSession> sessionsToUpdate = [
            SELECT Id, Escalated_by_Agentforce__c
            FROM MessagingSession
            WHERE Id IN :messagingSessionIds
        ];
        
        for (MessagingSession session : sessionsToUpdate) {
            session.Escalated_by_Agentforce__c = true;
        }
        
        try {
            update sessionsToUpdate;
            return true;
        } catch (DmlException e) {
            System.debug('Error updating Escalated_by_Agentforce__c: ' + e.getMessage());
        }
        return false;
    }
    
    // Method to update Handled_by_Agentforce__c
    private static Boolean updateHandled(List<Id> messagingSessionIds) {
        List<MessagingSession> sessionsToUpdate = [
            SELECT Id, Handled_by_Agentforce__c
            FROM MessagingSession
            WHERE Id IN :messagingSessionIds
        ];

        for (MessagingSession session : sessionsToUpdate) {
            session.Handled_by_Agentforce__c = true;
        }
        
        try {
            update sessionsToUpdate;
            return true;
        } catch (DmlException e) {
            System.debug('Error updating Handled_by_Agentforce__c: ' + e.getMessage());
        }
        return false;
    }
}