/*
Invocable Apex by Agentforce to fetch smartpay related application
Input is SMP Application number

Created by: Hao Shen (SFDC)
Created date: 2025-01-21

 */ 
public without sharing class AgentFetchSMPApplication {
    @InvocableMethod(label='Agent Fetch Smartpay Application')
    public static List<FlowOutputs> FetchApplication(List<FlowInputs> input) {    
        
        String smpApplicationNumber = input[0].smpApplicationNumber;
        
        FlowOutputs fout = new FlowOutputs();
        fout.caseId        = '';
        fout.caseStatus    = '';
        fout.smpApplicationId = '';
        
		List<smp_Smartpay_Application__c> smpApps = [select id, smp_Case__c from smp_Smartpay_Application__c 
                                                     where smp_Application_Number__c =: smpApplicationNumber limit 1];
        
        if(smpApps.size() > 0) {
            List<Case> newCases = [select id, Status  from Case
                                  where id =: smpApps[0].smp_Case__c limit 1];
            
            if(newCases.size() > 0) {
                Case newCase = new Case();
                newCase = newCases[0];
                fout.caseId        = newCase.id;
                fout.caseStatus    = newCase.Status;
                fout.smpApplicationId = smpApps[0].id;             
            }       
        }
                
        List<FlowOutputs> results = new List<FlowOutputs>();
        results.add(fout);
        return results;
    }
    
    //input details that comes to apex from flow
    public class FlowInputs {     
        @InvocableVariable (required=true)
        public String smpApplicationNumber;
    }
    
    // output details which goes from apex to flow
    public class FlowOutputs {    
        @InvocableVariable (required=true)
        public String caseId;
       
        @InvocableVariable (required=false)
        public String caseStatus;
        
        @InvocableVariable (required=false)
        public String smpApplicationId;
    }
}