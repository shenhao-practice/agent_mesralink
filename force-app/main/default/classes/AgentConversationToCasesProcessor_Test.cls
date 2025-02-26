@isTest
public class AgentConversationToCasesProcessor_Test {

    @testSetup
    static void setup() {
        // Create a RecordType for Case if it doesn't exist
        RecordType rt = [SELECT Id FROM RecordType WHERE DeveloperName = 'PDBContactCenter' AND SObjectType = 'Case' LIMIT 1];

        // Create a Test Account and Contact
        Account testAccount = new Account(Name='Test Account');
        insert testAccount;
        
        Contact testContact = new Contact(FirstName='Test', LastName='Contact', AccountId=testAccount.Id);
        insert testContact;
        
        // Create a Parent Case
        Case parentCase = new Case(
            AccountId = testAccount.Id,
            ContactId = testContact.Id,
            Subject = 'Parent Case',
            RecordTypeId = rt.Id
        );
        insert parentCase;
    }

    @isTest
    static void testCreateChildCases() {
        // Retrieve the inserted parent case
        Case parentCase = [SELECT Id FROM Case LIMIT 1];
        
        String jsonInput = '{"total_groups":1,"conversation_pairs":[{"group_number":1,"customer":{"message":"Customer message","timestamp":"2025-01-01T12:00:00Z"},"agent":{"message":"Agent message","timestamp":"2025-01-01T12:05:00Z"},"feedback":{"message":"Feedback message","flag":"true","timestamp":"2025-01-01T12:10:00Z"},"category2":"Enquiry","in_session":true}]}';
        
        AgentConversationToCasesProcessor.FlowInputs flowInput = new AgentConversationToCasesProcessor.FlowInputs();
        flowInput.jsonInput = jsonInput;
        flowInput.parentCaseId = parentCase.Id;
        
        Test.startTest();
        AgentConversationToCasesProcessor.createChildCases(new List<AgentConversationToCasesProcessor.FlowInputs>{flowInput});
        Test.stopTest();
        
        // Verify that the child case was created
        List<Case> childCases = [SELECT Id, ParentId, Description, ASA_Feedback__c, AccountId, ContactId, OwnerId, PDBCaseCategory1__c, PDBCaseCategory2__c, Origin, Status, Subject, Reminder_Counter__c, PDBSLAStartDate__c, PDBSLAActualEndDate__c FROM Case WHERE ParentId = :parentCase.Id];
        System.assertEquals(1, childCases.size(), 'Expected only one child case to be created');
        Case childCase = childCases[0];
        System.assertEquals(parentCase.Id, childCase.ParentId);
        System.assertEquals('Yes', childCase.ASA_Feedback__c);
        System.assertEquals('Enquiry', childCase.PDBCaseCategory2__c);
        System.assertEquals('Closed', childCase.Status);
    }

    @isTest
    static void testNoParams() {
        Test.startTest();
        AgentConversationToCasesProcessor.createChildCases(null);
        AgentConversationToCasesProcessor.createChildCases(new List<AgentConversationToCasesProcessor.FlowInputs>());
        Test.stopTest();
    }

    @isTest
    static void testParentCaseNotFound() {
        String jsonInput = '{"total_groups":1,"conversation_pairs":[{"group_number":1,"customer":{"message":"Customer message","timestamp":"2025-01-01T12:00:00Z"},"agent":{"message":"Agent message","timestamp":"2025-01-01T12:05:00Z"},"feedback":{"message":"Feedback message","flag":"true","timestamp":"2025-01-01T12:10:00Z"},"category2":"Inquiry","in_session":true}]}';
        
        AgentConversationToCasesProcessor.FlowInputs flowInput = new AgentConversationToCasesProcessor.FlowInputs();
        flowInput.jsonInput = jsonInput;
        flowInput.parentCaseId = 'nonexistentCaseId';
        
        Test.startTest();
        try {
            AgentConversationToCasesProcessor.createChildCases(new List<AgentConversationToCasesProcessor.FlowInputs>{flowInput});
            System.assert(false, 'Exception should have been thrown');
        } catch (AgentConversationToCasesProcessor.InvocableActionException e) {
            System.assert(e.getMessage().contains('Parent Case not found with ID'));
        }
        Test.stopTest();
    }
    
    // MockHttpResponseGenerator class for mocking HTTP callouts
    private class MockHttpResponseGenerator implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"message": "Mock response"}');
            res.setStatusCode(200);
            return res;
        }
    }
}