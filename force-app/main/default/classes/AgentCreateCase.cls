/* 
Invocable Apex by Agentforce to create case with below pseudocode
- Create Case (store truncated conversatino transcript into description)
- Link case with Messaging Session, Messaging End User
- Search and link Customer B2C account id
> Match using Mobile + Name, enhanced the Mobile number variations for different MY and SG format
- Create new B2C account if not found

Created by: Hao Shen (SFDC)
Created date: 2024-02-11
*/
public without sharing class AgentCreateCase {
    // Custom exception class
    public class AgentCreateCaseException extends Exception {}
    
    // Constants
    private static final String RECORD_TYPE_PDB_CONTACT_CENTER = 'PDBContactCenter';
    private static final String RECORD_TYPE_PERSON_ACCOUNT = 'PersonAccount';
    private static final String ORIGIN_WHATSAPP = 'WhatsApp';
    private static final String STATUS_CLOSED = 'Closed';
    private static final String LANGUAGE_ENGLISH = 'English';
    private static final String RECORD_TYPE_STATION = 'PDB_Site';
    
    @InvocableMethod(label='Agentforce Create Case')
    public static List<FlowOutputs> createCase(List<FlowInputs> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            throw new AgentCreateCaseException('Input parameters cannot be null or empty');
        }
        
        try {
            FlowInputs input = inputs[0];
            MessagingSession msgSession = getMessagingSession(input.messagingSessionId);
            MessagingEndUser msgEndUser = getMessagingEndUser(msgSession.MessagingEndUserId);
            
            // Create case with all related data
            Case newCase = createCaseRecord(msgSession, msgEndUser);
            
            // Update related records
            updateRelatedRecords(input.messagingSessionId, newCase, msgEndUser);
            
            return new List<FlowOutputs>{createFlowOutput(newCase.Id, msgEndUser.Name)};
        } catch (Exception e) {
            throw new AgentCreateCaseException('Error creating case: ' + e.getMessage());
        }
    }
    
    private static MessagingSession getMessagingSession(Id sessionId) {
        List<MessagingSession> sessions = [
            SELECT Id, Status, PreviewDetails, StartTime, EndTime, 
                   ConversationId, ChannelKey, ChannelName, ChannelType, 
                   MessagingEndUserId, EndUserAccountId, EndUserContactId
            FROM MessagingSession 
            WHERE Id = :sessionId 
            LIMIT 1
        ];
        
        if (sessions.isEmpty()) {
            throw new AgentCreateCaseException('Messaging Session not found');
        }
        return sessions[0];
    }
    
    private static MessagingEndUser getMessagingEndUser(Id endUserId) {
        List<MessagingEndUser> endUsers = [
            SELECT Id, Name, MessagingPlatformKey, IsoCountryCode, AccountId, ContactId
            FROM MessagingEndUser 
            WHERE Id = :endUserId 
            LIMIT 1
        ];
        
        if (endUsers.isEmpty()) {
            throw new AgentCreateCaseException('Messaging End User not found');
        }
        return endUsers[0];
    }
    
    private static Case createCaseRecord(MessagingSession msgSession, MessagingEndUser msgEndUser) {
        // Find or create customer account
        String mobile = msgEndUser.MessagingPlatformKey;
        String countryCode = msgEndUser.IsoCountryCode;
        
        String description = '';
        String location    = '';

        Map<String, String> msgMap = new Map<String, String>();
        
        if (!Test.isRunningTest()) {msgMap = getConversationEntriesFiltered(msgSession, msgEndUser.Name);}
        
        if (msgMap != null && msgMap.containsKey('des')) {description = msgMap.get('des');}
        if (msgMap != null && msgMap.containsKey('loc')) {location = msgMap.get('loc');}

        Account customerAcc = searchAndLinkCustomer(mobile, countryCode, msgEndUser.Name);

        //Assign station and dealer account
        Account station;
        Account dealer;
        User caseOwner;
        if (location <> '') {
            List<Account> stations = [select Id, Name, ParentId from Account where Site_Id__c = :location 
                                      and RecordType.DeveloperName = :RECORD_TYPE_STATION
                                      order by LastModifiedDate desc limit 1];
            if (stations.size()==1) {
                station = stations[0];
                System.debug('station: '+station);
                
                List<Account> dealers = [select Id, Name, ParentId from Account where Id = :station.ParentId];
                if (dealers.size()==1) {
                    dealer = dealers[0];
                    System.debug('dealer: '+dealer);
                    
                    List<User> caseOwners = [select Id, Name from User where ContactId in (select ContactId from AccountContactRelation where AccountId = :station.ParentId and IsActive = True AND Contact.Partner_Role__c = 'Dealer') order by LastModifiedDate Desc];
                    if (caseOwners.size()>0) {caseOwner = caseOwners[0];}
                }
            }
        }
        // Get case record type
        Id recordTypeId = getRecordTypeId(RECORD_TYPE_PDB_CONTACT_CENTER, 'Case');
        
        Case newCase = new Case(
            PersonAccount__c = customerAcc?.Id,  // PersonAccount__c = (customerAcc != null) ? customerAcc.Id : null;
            ContactId = customerAcc?.PersonContactId,
            RecordTypeId = recordTypeId,
            Origin = ORIGIN_WHATSAPP,
            Status = STATUS_CLOSED,
            Agent_s_Remark__c = 'Agentforce',
            Subject = '[WA] Agentforce Master ' + OmniConstants.ENQUIRY,
            Reminder_Counter__c = 0,
            Preferred_Language__c = LANGUAGE_ENGLISH,
            PDBSLAStartDate__c = msgSession.StartTime,
            PDBSLAActualEndDate__c = msgSession.EndTime,
            PDBCaseCategory1__c = OmniConstants.ENQUIRY,
            Site__c = station?.Id,
            Dealer__c = dealer?.Id,
            Description = description
        );
        
        if(caseOwner != null) { newCase.OwnerId = caseOwner.Id;}
        
        insert newCase;
        return newCase;
    }
    
    private static Map<String, String> getConversationEntriesFiltered(MessagingSession session, String userName) {
        Map<String, String> msgMap = new Map<String, String>();
        if (session.ConversationId == null) return msgMap;
        
        Boolean findLocation = false; String conversation = ''; String locationCode = '';
        
        List<Conversation> conversations = [SELECT ConversationIdentifier FROM Conversation WHERE Id = :session.ConversationId LIMIT 1];
        
        if (conversations.isEmpty()) return msgMap;
        
        Datetime sessionStart = session.StartTime?.addHours(8);
        Datetime sessionEnd = session.EndTime?.addHours(8);
        
        OmniGetConversationEntries ce = new OmniGetConversationEntries();
        Map<Long, OmniConversationEntries.ConversationEntry> entries = 
            ce.getConversationEntries(conversations[0].ConversationIdentifier, '*');
                
        for (Long timestamp : entries.keySet()) {
            OmniConversationEntries.ConversationEntry entry = entries.get(timestamp);
            Datetime entryTime = Datetime.valueOf(entry.clientDatetime);
            
            if (entryTime >= sessionStart && (sessionEnd == null || entryTime <= sessionEnd)) {
                String role = (entry.sender.role == 'Chatbot') ? 'Melissa' : userName;
                conversation += '[' + entry.clientDatetime + ' ' + role + ']:\n' + entry.messageText + '\n\n';
                
                // find location in conversation message
                if (!findLocation && role != 'Chatbot') {locationCode = findLocation(entry.messageText);
                    if (!String.isBlank(locationCode)) {findLocation = true;}
                }                
            }
        }
        msgMap.put('des', conversation); msgMap.put('loc', locationCode);
        return msgMap;
    }
    
    @TestVisible
    private static String findLocation(String message) {
        String locationCode = '';
        if (String.isBlank(message)) return locationCode;
        if (message.containsIgnoreCase('[') && message.containsIgnoreCase(']')) {
            locationCode = OmniGetLocation.extractLocation(message, '[', ']', 0);
        }
        else if (message.containsIgnoreCase('&lt;') && message.containsIgnoreCase('&gt;')) {
            locationCode = OmniGetLocation.extractLocation(message, '&lt;', '&gt;', 3);
        }
        return locationCode;
    }
    
    private static void updateRelatedRecords(Id sessionId, Case newCase, MessagingEndUser endUser) {
        // Update MessagingSession
        MessagingSession session = new MessagingSession(
            Id = sessionId,
            CaseId = newCase.Id
        );
        update session;
        
        // Update MessagingEndUser
        MessagingEndUser updatedEndUser = new MessagingEndUser(
            Id = endUser.Id,
            AccountId = newCase.PersonAccount__c,
            ContactId = newCase.ContactId
        );
        update updatedEndUser;
    }
    
    private static Account searchAndLinkCustomer(String mobile, String countryCode, String name) {
        if (String.isBlank(mobile)) {
            throw new AgentCreateCaseException('Mobile number is required');
        }
        
        Set<String> mobileVariations = getMobileVariations(mobile, countryCode);
        List<Account> existingAccounts = [
            SELECT Id, Name, PersonContactId, PersonMobilePhone, PersonEmail
            FROM Account 
            WHERE PersonMobilePhone IN :mobileVariations
            AND RecordType.DeveloperName = :RECORD_TYPE_PERSON_ACCOUNT
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        
        return !existingAccounts.isEmpty() ? existingAccounts[0] : createNewB2C(name, mobile);
    }
    
    private static Set<String> getMobileVariations(String mobile, String countryCode) {
        Set<String> variations = new Set<String>();
        if (String.isBlank(mobile)) return variations;
        
        // Clean the mobile number to only contain digits
        String cleanMobile = mobile.replaceAll('[^0-9]', '');
        
        // Define country codes
        Map<String, String> countryCodes = new Map<String, String>{
            'SG' => '65',
            'MY' => '60'
        };
        
        // Get the numeric country code
        String numericCountryCode = '';
        if (String.isNotBlank(countryCode) && countryCodes.containsKey(countryCode.toUpperCase())) {
            numericCountryCode = countryCodes.get(countryCode.toUpperCase());
        }
        
        // Handle numbers starting with a country code
        if (cleanMobile.startsWith('65') || cleanMobile.startsWith('60')) {
            String existingCountryCode = cleanMobile.substring(0, 2);
            String numberWithoutCountryCode = cleanMobile.substring(2);
            
            // Add variations without country code
            addVariations(variations, numberWithoutCountryCode);
            
            // Add variations with existing country code
            addVariations(variations, cleanMobile);
            
            // If a different country code is specified, add those variations too
            if (String.isNotBlank(numericCountryCode) && numericCountryCode != existingCountryCode) {
                addVariations(variations, numericCountryCode + numberWithoutCountryCode);
            }
        } else {
            // Number doesn't start with country code
            addVariations(variations, cleanMobile);
            
            // If country code is specified, add variations with that country code
            if (String.isNotBlank(numericCountryCode)) {
                addVariations(variations, numericCountryCode + cleanMobile);
            }
        }
        
        return variations;
    }
    
    private static void addVariations(Set<String> variations, String mobile) {
        // Basic formats
        variations.add(mobile);                    // Raw number
        variations.add('+' + mobile);             // With plus
        
        // Format with spaces (for 8-digit numbers)
        if (mobile.length() == 8) {
            variations.add(mobile.substring(0, 4) + ' ' + mobile.substring(4));
        }
        
        // Format with dashes
        if (mobile.length() >= 8) {
            String dashedNumber = mobile;
            if (mobile.length() == 8) {
                // For 8-digit numbers (e.g., Singapore format)
                dashedNumber = mobile.substring(0, 4) + '-' + mobile.substring(4);
            } else if (mobile.length() == 9) {
                // For 9-digit numbers (e.g., Malaysia mobile)
                dashedNumber = mobile.substring(0, 3) + '-' + mobile.substring(3, 6) + '-' + mobile.substring(6);
            } else if (mobile.length() == 10) {
                // For 10-digit numbers
                dashedNumber = mobile.substring(0, 4) + '-' + mobile.substring(4, 7) + '-' + mobile.substring(7);
            }
            variations.add(dashedNumber);
        }
        
        // Format with parentheses for country code
        if (mobile.startsWith('65') || mobile.startsWith('60')) {
            String countryCode = mobile.substring(0, 2);
            String rest = mobile.substring(2);
            variations.add('(' + countryCode + ')' + rest);
            variations.add('(' + countryCode + ') ' + rest);
        }
    }
    
    private static Id getRecordTypeId(String developerName, String objectType) {
        List<RecordType> recordTypes = [
            SELECT Id 
            FROM RecordType 
            WHERE DeveloperName = :developerName 
            AND SobjectType = :objectType 
            AND IsActive = true 
            LIMIT 1
        ];
        
        return !recordTypes.isEmpty() ? recordTypes[0].Id : null;
    }
    
    private static Account createNewB2C(String name, String mobile) {
        Id recordTypeId = getRecordTypeId(RECORD_TYPE_PERSON_ACCOUNT, 'Account');
        if (recordTypeId == null) {
            throw new AgentCreateCaseException('Person Account record type not found');
        }
        
        Account newAccount = new Account(
            RecordTypeId = recordTypeId,
            LastName = name,
            PersonMobilePhone = mobile,
            Is_Active__c = true,
            PDB_Contact_Type__pc = 'Public'
        );
        
        insert newAccount;
        return newAccount;
    }
    
    private static FlowOutputs createFlowOutput(Id caseId, String custName) {
        Case newCase = [
            SELECT Id, CaseNumber 
            FROM Case 
            WHERE Id = :caseId 
            LIMIT 1
        ];
        
        FlowOutputs output = new FlowOutputs();
        output.caseId = newCase.Id;
        output.caseNumber = newCase.CaseNumber;
        output.custName = custName;
        return output;
    }
    
    public class FlowInputs {     
        @InvocableVariable(required=true)
        public Id messagingSessionId;
    }
    
    public class FlowOutputs {    
        @InvocableVariable(required=true)
        public String caseId;
        @InvocableVariable(required=true)
        public String caseNumber;
        @InvocableVariable(required=false)
        public String custName;
    }
}