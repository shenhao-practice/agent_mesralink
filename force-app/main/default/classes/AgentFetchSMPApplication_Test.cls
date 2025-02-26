@isTest
public class AgentFetchSMPApplication_Test {
    
    @isTest
    static void testFetchApplication() {
        // Create a test Case record
        Case testCase = new Case(Status = 'New');
        insert testCase;
        
        // Create a test smp_Smartpay_Application__c record
        smp_Smartpay_Application__c testSMPApp = new smp_Smartpay_Application__c(
            smp_Application_Number__c = 'TEST123',
            smp_Case__c = testCase.Id,
            smp_Account_Type_Id__c = 'SomeAccountTypeId' // Ensure this field is populated
        );
        insert testSMPApp;
        
        // Prepare the input
        AgentFetchSMPApplication.FlowInputs input = new AgentFetchSMPApplication.FlowInputs();
        input.smpApplicationNumber = 'TEST123';
        List<AgentFetchSMPApplication.FlowInputs> inputs = new List<AgentFetchSMPApplication.FlowInputs>();
        inputs.add(input);
        
        // Call the method
        List<AgentFetchSMPApplication.FlowOutputs> results = AgentFetchSMPApplication.FetchApplication(inputs);
        
        // Validate the results
        System.assertEquals(1, results.size());
        AgentFetchSMPApplication.FlowOutputs output = results[0];
        System.assertEquals(testCase.Id, output.caseId);
        System.assertEquals('New', output.caseStatus);
        System.assertEquals(testSMPApp.Id, output.smpApplicationId);
    }
    
    @isTest
    static void testFetchApplicationNoMatch() {
        // Prepare the input with a non-existing application number
        AgentFetchSMPApplication.FlowInputs input = new AgentFetchSMPApplication.FlowInputs();
        input.smpApplicationNumber = 'NON_EXISTENT';
        List<AgentFetchSMPApplication.FlowInputs> inputs = new List<AgentFetchSMPApplication.FlowInputs>();
        inputs.add(input);
        
        // Call the method
        List<AgentFetchSMPApplication.FlowOutputs> results = AgentFetchSMPApplication.FetchApplication(inputs);
        
        // Validate the results
        System.assertEquals(1, results.size());
        AgentFetchSMPApplication.FlowOutputs output = results[0];
        System.assertEquals('', output.caseId);
        System.assertEquals('', output.caseStatus);
        System.assertEquals('', output.smpApplicationId);
    }
}