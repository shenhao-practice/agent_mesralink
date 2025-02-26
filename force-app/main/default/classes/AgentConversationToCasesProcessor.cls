/*
Invocable Apex by Agentforce to create child cases from conversation content in 

Created by: Hao Shen (SFDC)
Created date: 2024-01-21
*/

public without sharing class AgentConversationToCasesProcessor {
    
    private static String exclude_Category = 'Others';

    @InvocableMethod(label='Create Child Cases from Conversation' description='Creates child cases for each conversation pair')
    public static void createChildCases(List<FlowInputs> params) {
        if (params == null || params.isEmpty()) return;
        
        FlowInputs input = params[0];
        List<Case> parentCases = new List<Case>();
        
        // New Case = PDBContactCenter, Close Case = PDB_Closed_Case
        RecordType rt;
        List<RecordType> rts = [select Id from RecordType where DeveloperName = 'PDBContactCenter' and SobjectType = 'Case' and IsActive = true];
        if (rts.size()==1) {
            rt = rts[0];
            System.debug('record type PDBContactCenter: '+rt);
        }
        
        List<Case> parentCaseList = [Select Id, AccountId, OwnerId, ContactId from Case where Id =: input.parentCaseId]; 

        try {
            
            // Parse JSON input
            ConversationData convData = (ConversationData)JSON.deserialize(
                input.jsonInput, 
                ConversationData.class
            );

			/*
            // Parse JSON input using AgentLargeJsonHelper
            List<Map<String, Object>> parsedData = AgentLargeJsonHelper.processLargeJsonBlob(input.jsonInput, false);
            Map<String, Object> convDataMap = parsedData.isEmpty() ? null : parsedData[0];

            ConversationData convData = (ConversationData)JSON.deserialize(JSON.serialize(convDataMap), ConversationData.class);
			*/
            
            
            // Verify parent case exists
            if (String.isNotBlank(input.parentCaseId)) {
                parentCases = [SELECT Id FROM Case WHERE Id = :input.parentCaseId LIMIT 1];
                if (parentCases.isEmpty()) {
                    throw new InvocableActionException('Parent Case not found with ID: ' + input.parentCaseId);
                }
            }
            
            // System.debug('convData: '+convData);
            
            List<Case> casesToInsert = new List<Case>();
            
            // Loop through conversation pairs
            for (ConversationPair pair : convData.conversation_pairs) {
                                
                // if (pair.in_session != true) continue;
                
                // if category2 is unknown, no case to create
                if (pair.category2 == exclude_Category) continue;
                
                // if customer or agent message is empty, no case to create
                if (String.isBlank(pair.customer?.message) || String.isBlank(pair.agent?.message)) continue;
                
                // Create child case
                Case childCase = new Case();

                childCase.RecordTypeId = rt.Id;

                if (String.isNotBlank(input.parentCaseId)) {
                    childCase.ParentId = input.parentCaseId;
                }
                
                childCase.Description = buildDescription(pair, input.custName);
                
                if (pair.feedback != null) {
                    Boolean flagValue = pair.feedback.getFlag();
                    if (flagValue != null) {
                        childCase.ASA_Feedback__c = flagValue ? 'Yes' : 'No';
                    }
                }
                
                childCase.AccountId = parentCaseList[0].AccountId;
                childCase.ContactId = parentCaseList[0].ContactId;
                childCase.OwnerId   = parentCaseList[0].OwnerId;

                childCase.PDBCaseCategory1__c = OmniConstants.ENQUIRY;
                childCase.PDBCaseCategory2__c = pair.category2;
                childCase.PDBCaseCategory3__c = pair.category3;
                childCase.PDBCaseCategory4__c = pair.category4;

                childCase.Origin = 'WhatsApp';
                childCase.Status = 'Closed';
                childCase.Subject = '[WA] Agentforce ' + OmniConstants.ENQUIRY + ' Support';
                childCase.Agent_s_Remark__c = 'Agentforce';
                childCase.Reminder_Counter__c = 0;
                
                if (pair.customer.timestamp < pair.agent.timestamp) {
					childCase.PDBSLAStartDate__c = Datetime.valueOfGmt(pair.customer.timestamp.replace('T', ' '));
                    childCase.PDBSLAActualEndDate__c = Datetime.valueOfGmt(pair.agent.timestamp.replace('T', ' ')); 
                } else {
                    childCase.PDBSLAStartDate__c = Datetime.valueOfGmt(pair.customer.timestamp.replace('T', ' '));
	                childCase.PDBSLAActualEndDate__c = System.now();  
                }
                
                
                casesToInsert.add(childCase);
            }
            
            // Insert cases if any
            if (!casesToInsert.isEmpty()) {
                insert casesToInsert;
            }
            
            System.debug('Newly Created Case'+casesToInsert);
            
        } catch (Exception e) {
            // Handle any errors that occur during processing
            throw new InvocableActionException('Error processing conversation: ' + e.getMessage());
        }
    }
    
    private static String buildDescription(ConversationPair pair, String custName) {
        String description = '';
        if (String.isBlank(custName)) custName = 'Customer';
    
        // Check if both customer and agent messages exist
        if (pair.customer?.timestamp != null && pair.agent?.timestamp != null) {
            // Compare timestamps
            if (pair.customer.timestamp < pair.agent.timestamp) {
                // Add customer message first
                if (String.isNotBlank(pair.customer?.message)) {
                    description += custName + ' (' + pair.customer.timestamp + '):\n';
                    description += pair.customer.message + '\n\n';
                }
                // Add agent message second
                if (String.isNotBlank(pair.agent?.message)) {
                    description += 'Melissa (' + pair.agent.timestamp + '):\n';
                    description += pair.agent.message;
                }
            } else {
                // Add agent message first
                if (String.isNotBlank(pair.agent?.message)) {
                    description += 'Melissa (' + pair.agent.timestamp + '):\n';
                    description += pair.agent.message + '\n\n';
                }
                // Add customer message second
                if (String.isNotBlank(pair.customer?.message)) {
                    description += custName + ' (' + pair.customer.timestamp + '):\n';
                    description += pair.customer.message;
                }
            }
        } else {
            // Add customer message if exists
            if (String.isNotBlank(pair.customer?.message)) {
                description += custName + ' (' + (pair.customer.timestamp != null ? pair.customer.timestamp : '') + '):\n';
                description += pair.customer.message + '\n\n';
            }
    
            // Add agent message if exists
            if (String.isNotBlank(pair.agent?.message)) {
                description += 'Melissa (' + (pair.agent.timestamp != null ? pair.agent.timestamp : '') + '):\n';
                description += pair.agent.message;
            }
        }
    
        return description;
    }
    
    public class InvocableActionException extends Exception {}


    
    // Wrapper class for conversation JSON structure
    public class ConversationData {
        public Integer total_groups;
        public List<ConversationPair> conversation_pairs;
    }
    
    public class ConversationPair {
        public Integer group_number;
        public CustomMessage customer;
        public CustomMessage agent;
        public Feedback feedback;
        public String category2;
        public String category3;
        public String category4;
        public Boolean in_session;
    }
    
    public class CustomMessage {
        public String message;
        public String timestamp;
    }
    
    public class Feedback {
        public String message;
        public String flag;  // Change from Object to String
        public String timestamp;

        // Add a method to safely get the boolean value
        public Boolean getFlag() {
            if (String.isEmpty(flag)) {
                return null;
            }
            return flag.equalsIgnoreCase('true');
        }
    }

    // Wrapper class for input parameters from Flow
    public class FlowInputs {
        @InvocableVariable(required=true)
        public String jsonInput; // public Blob jsonInput; // blob is not support in flow
        
        @InvocableVariable(required=false)
        public String parentCaseId;
        
        @InvocableVariable(required=false)
        public String custName;
    }    
}