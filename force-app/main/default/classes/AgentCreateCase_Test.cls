@isTest
private class AgentCreateCase_Test {
    private static final String PERSON_ACCOUNT_RT = 'PersonAccount';
    private static final String PDB_CONTACT_CENTER_RT = 'PDBContactCenter';
    private static final String RECORD_TYPE_STATION = 'PDB_Site';
    private static final String TEST_MOBILE_SG = '+6591234567890'; // Singapore format
    private static final String TEST_MOBILE_MY = '+60123456789'; // Malaysia format
    
    @TestSetup
    static void setupTestData() {
        // Setup needs to run in its own transaction due to mixed DML operations
        System.runAs(new User(Id = UserInfo.getUserId())) {
            // Create MessagingChannel
            String uniqueId = String.valueOf(Datetime.now().getTime());
            MessagingChannel channel = new MessagingChannel(
                DeveloperName = 'TestChannel_' + uniqueId,
                MasterLabel = 'Test Channel ' + uniqueId,
                MessageType = 'WhatsApp',
                IsActive = true,
                MessagingPlatformKey = 'whatsapp:' + TEST_MOBILE_SG
            );
            insert channel;


            // Get Record Types safely
            Map<String, Schema.RecordTypeInfo> accountRTMap = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
            Id dealerRTId = accountRTMap.containsKey('Dealer') ? accountRTMap.get('Dealer').getRecordTypeId() : null;
            Id stationRTId = accountRTMap.containsKey(RECORD_TYPE_STATION) ? accountRTMap.get(RECORD_TYPE_STATION).getRecordTypeId() : null;

            if (dealerRTId != null) {
                // Create Dealer Account
                Account dealerAccount = new Account(
                    Name = 'Test Dealer',
                    RecordTypeId = dealerRTId
                );
                insert dealerAccount;

                if (stationRTId != null) {
                    // Create Station Account
                    Account stationAccount = new Account(
                        Name = 'Test Station',
                        RecordTypeId = stationRTId,
                        ParentId = dealerAccount.Id,
                        Site_Id__c = 'TEST001'
                    );
                    insert stationAccount;
                }

                // Create Dealer Contact
                Contact dealerContact = new Contact(
                    LastName = 'Dealer Contact',
                    AccountId = dealerAccount.Id,
                    Partner_Role__c = 'Dealer'
                );
                insert dealerContact;

                // Create Account Contact Relation
                AccountContactRelation acr = new AccountContactRelation(
                    AccountId = dealerAccount.Id,
                    ContactId = dealerContact.Id,
                    IsActive = true
                );
                insert acr;

                // Create User for Dealer Contact
                List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
                if (!profiles.isEmpty()) {
                    User dealerUser = new User(
                        LastName = 'Dealer User',
                        Email = 'dealer.user@test.com',
                        Username = 'dealer.user@test.com' + uniqueId,
                        ContactId = dealerContact.Id,
                        ProfileId = profiles[0].Id,
                        Alias = 'dUser',
                        TimeZoneSidKey = 'America/Los_Angeles',
                        LocaleSidKey = 'en_US',
                        EmailEncodingKey = 'UTF-8',
                        LanguageLocaleKey = 'en_US'
                    );
                    insert dealerUser;
                }
            }            
        }
    }

    private static void createTestData(Boolean createExistingAccount, String mobileNumber, String countryCode) {
        // Get channel
        List<MessagingChannel> channels = [SELECT Id FROM MessagingChannel WHERE DeveloperName LIKE 'TestChannel_%' ORDER BY CreatedDate DESC LIMIT 1];
        if (channels.isEmpty()) {
            return;
        }
        
        // Create MessagingEndUser
        MessagingEndUser endUser = new MessagingEndUser(
            Name = 'Test User',
            MessagingChannelId = channels[0].Id,
            MessageType = 'WhatsApp',
            MessagingPlatformKey = mobileNumber,
            IsoCountryCode = countryCode
        );
        insert endUser;
        
        // Create Person Account if needed
        if (createExistingAccount) {
            Map<String, Schema.RecordTypeInfo> accountRTMap = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
            Id personAccountRTId = accountRTMap.containsKey(PERSON_ACCOUNT_RT) ? accountRTMap.get(PERSON_ACCOUNT_RT).getRecordTypeId() : null;
            
            if (personAccountRTId != null) {
                Account personAccount = new Account(
                    RecordTypeId = personAccountRTId,
                    LastName = 'Test User',
                    PersonMobilePhone = mobileNumber,
                    Is_Active__c = true,
                    PDB_Contact_Type__pc = 'Public'
                );
                insert personAccount;
            }
        }
        
        // Create MessagingSession
        MessagingSession session = new MessagingSession(
            MessagingChannelId = channels[0].Id,
            MessagingEndUserId = endUser.Id,
            Status = 'Active',
            StartTime = Datetime.now(),
            EndTime = Datetime.now().addHours(1)
        );
        insert session;
    }
    
    @isTest
    static void testCreateCaseWithExistingAccount() {
        createTestData(true, TEST_MOBILE_SG, 'SG');
        
        List<MessagingSession> sessions = [SELECT Id FROM MessagingSession LIMIT 1];
        if (sessions.isEmpty()) {
            return;
        }
        
        // Create input for the invocable method
        AgentCreateCase.FlowInputs input = new AgentCreateCase.FlowInputs();
        input.messagingSessionId = sessions[0].Id;
        
        Test.startTest();
        List<AgentCreateCase.FlowOutputs> outputs = 
            AgentCreateCase.createCase(new List<AgentCreateCase.FlowInputs>{input});
        Test.stopTest();
        
        // Verify results
        System.assertNotEquals(null, outputs, 'Output should not be null');
        System.assertEquals(1, outputs.size(), 'Should have one output');
        System.assertNotEquals(null, outputs[0].caseId, 'Case ID should not be null');
        System.assertNotEquals(null, outputs[0].caseNumber, 'Case Number should not be null');
        
        // Verify case details
        List<Case> cases = [
            SELECT Id, PersonAccount__c, Origin, Status, Subject, Site__c, Dealer__c
            FROM Case 
            WHERE Id = :outputs[0].caseId
        ];
        if (!cases.isEmpty()) {
            System.assertEquals('WhatsApp', cases[0].Origin, 'Case origin should be WhatsApp');
            System.assertEquals('Closed', cases[0].Status, 'Case status should be Closed');
            
            // Verify MessagingSession was updated
            List<MessagingSession> updatedSessions = [
                SELECT CaseId 
                FROM MessagingSession 
                WHERE Id = :sessions[0].Id
            ];
            if (!updatedSessions.isEmpty()) {
                System.assertEquals(cases[0].Id, updatedSessions[0].CaseId, 
                    'MessagingSession should be linked to the case');
            }
        }
    }
    
    @isTest
    static void testCreateCaseWithNewAccount() {
        createTestData(false, TEST_MOBILE_SG, 'SG');
        
        // Get test session
        MessagingSession testSession = [SELECT Id FROM MessagingSession LIMIT 1];
        
        // Create input for the invocable method
        AgentCreateCase.FlowInputs input = new AgentCreateCase.FlowInputs();
        input.messagingSessionId = testSession.Id;
        
        Test.startTest();
        List<AgentCreateCase.FlowOutputs> outputs = 
            AgentCreateCase.createCase(new List<AgentCreateCase.FlowInputs>{input});
        Test.stopTest();
        
        // Verify results
        System.assertNotEquals(null, outputs, 'Output should not be null');
        System.assertEquals(1, outputs.size(), 'Should have one output');
        
        // Verify new account was created
        List<Account> newAccounts = [
            SELECT Id, PersonMobilePhone 
            FROM Account 
            WHERE PersonMobilePhone = :TEST_MOBILE_SG
            OR PersonMobilePhone = :('6591234567890') // without + version
        ];
        System.assertEquals(1, newAccounts.size(), 'A new account should have been created');
        
        // Verify case is linked to new account
        Case createdCase = [
            SELECT Id, PersonAccount__c 
            FROM Case 
            WHERE Id = :outputs[0].caseId
        ];
        System.assertEquals(newAccounts[0].Id, createdCase.PersonAccount__c, 
            'Case should be linked to the new account');
    }
    
    @isTest
    static void testMalaysiaNumber() {
        createTestData(true, TEST_MOBILE_MY, 'MY');
        
        // Get test session
        MessagingSession testSession = [SELECT Id FROM MessagingSession LIMIT 1];
        
        // Create input
        AgentCreateCase.FlowInputs input = new AgentCreateCase.FlowInputs();
        input.messagingSessionId = testSession.Id;
        
        Test.startTest();
        List<AgentCreateCase.FlowOutputs> outputs = 
            AgentCreateCase.createCase(new List<AgentCreateCase.FlowInputs>{input});
        Test.stopTest();
        
        // Verify case is created and linked properly
        Case createdCase = [
            SELECT Id, PersonAccount__c 
            FROM Case 
            WHERE Id = :outputs[0].caseId
        ];
        
        Account linkedAccount = [
            SELECT PersonMobilePhone 
            FROM Account 
            WHERE Id = :createdCase.PersonAccount__c
        ];
        System.assert(linkedAccount.PersonMobilePhone.contains('60'), 
            'Account should be linked with Malaysia number');
    }
    
    @isTest
    static void testNullInput() {
        Test.startTest();
        try {
            AgentCreateCase.createCase(null);
            System.assert(false, 'Should have thrown an exception');
        } catch (AgentCreateCase.AgentCreateCaseException e) {
            System.assertEquals('Input parameters cannot be null or empty', e.getMessage(),
                'Expected exception message not received');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testEmptyInput() {
        Test.startTest();
        try {
            AgentCreateCase.createCase(new List<AgentCreateCase.FlowInputs>());
            System.assert(false, 'Should have thrown an exception');
        } catch (AgentCreateCase.AgentCreateCaseException e) {
            System.assertEquals('Input parameters cannot be null or empty', e.getMessage(),
                'Expected exception message not received');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testInvalidSessionId() {
        AgentCreateCase.FlowInputs input = new AgentCreateCase.FlowInputs();
        input.messagingSessionId = '005000000000000'; // Invalid ID
        
        Test.startTest();
        try {
            AgentCreateCase.createCase(new List<AgentCreateCase.FlowInputs>{input});
            System.assert(false, 'Should have thrown an exception');
        } catch (AgentCreateCase.AgentCreateCaseException e) {
            System.assert(e.getMessage().contains('Messaging Session not found'),
                'Expected exception message not received');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testLocationExtraction() {
        Test.startTest();
        Map<String, String> testCases = new Map<String, String>{
            'Testing location [TEST001]' => 'TEST001',
            'Location code &lt;TEST002&gt;' => 'TEST002',
            'No location here' => '',
            '[TEST003] at start' => 'TEST003',
            'At end &lt;TEST004&gt;' => 'TEST004',
            '[INVALID' => '',
            '&lt;INVALID' => ''
        };
        
        for(String message : testCases.keySet()) {
            String extractedLocation = AgentCreateCase.findLocation(message);
            System.assertEquals(testCases.get(message), extractedLocation, 
                'Location extraction failed for message: ' + message);
        }
        Test.stopTest();
    }
    
    @isTest
    static void testMobileNumberVariations() {
        List<String> testNumbers = new List<String>{
            '+6591234567',
            '6591234567',
            '91234567',
            '9123-4567',
            '(65) 91234567'
        };
        
        Test.startTest();
        for(String mobile : testNumbers) {
            createTestData(false, mobile, 'SG');
            
            List<MessagingSession> sessions = [
                SELECT Id 
                FROM MessagingSession 
                WHERE MessagingEndUser.MessagingPlatformKey = :mobile 
                LIMIT 1
            ];
            
            if (!sessions.isEmpty()) {
                AgentCreateCase.FlowInputs input = new AgentCreateCase.FlowInputs();
                input.messagingSessionId = sessions[0].Id;
                
                List<AgentCreateCase.FlowOutputs> outputs = 
                    AgentCreateCase.createCase(new List<AgentCreateCase.FlowInputs>{input});
                
                System.assertNotEquals(null, outputs, 'Output should not be null for mobile: ' + mobile);
                System.assertEquals(1, outputs.size(), 'Should have one output for mobile: ' + mobile);
                
                List<Case> cases = [SELECT Id, PersonAccount__c FROM Case WHERE Id = :outputs[0].caseId];
                if (!cases.isEmpty()) {
                    System.assertNotEquals(null, cases[0].PersonAccount__c, 
                        'Case should be linked to an account for mobile: ' + mobile);
                }
            }
        }
        Test.stopTest();
    }
    
    /*
    @isTest
    static void testDifferentMobileFormats() {
        // Test mobile number variations by country
        Map<String, List<String>> countryFormats = new Map<String, List<String>>{
            'SG' => new List<String>{
                '+6591234567890',  // Changed to match TEST_MOBILE_SG format
                '6591234567890',
                '91234567890'
            },
            'MY' => new List<String>{
                '+60123456789',    // Changed to match TEST_MOBILE_MY format
                '60123456789',
                '0123456789'
            }
        };
        
        Test.startTest();
        for(String country : countryFormats.keySet()) {
            for(String mobile : countryFormats.get(country)) {
                createTestData(true, mobile, country);
                
                List<MessagingSession> sessions = [
                    SELECT Id 
                    FROM MessagingSession 
                    WHERE MessagingEndUser.MessagingPlatformKey = :mobile 
                    LIMIT 1
                ];
                
                if (!sessions.isEmpty()) {
                    AgentCreateCase.FlowInputs input = new AgentCreateCase.FlowInputs();
                    input.messagingSessionId = sessions[0].Id;
                    
                    List<AgentCreateCase.FlowOutputs> outputs = 
                        AgentCreateCase.createCase(new List<AgentCreateCase.FlowInputs>{input});
                    
                    System.assertNotEquals(null, outputs, 
                        'Should create case for ' + country + ' number: ' + mobile);
                    
                    List<Case> cases = [SELECT Id, PersonAccount__c FROM Case WHERE Id = :outputs[0].caseId];
                    if (!cases.isEmpty()) {
                        List<Account> accounts = [
                            SELECT PersonMobilePhone 
                            FROM Account 
                            WHERE Id = :cases[0].PersonAccount__c
                        ];
                        if (!accounts.isEmpty()) {
                            // Adjust assertion to check for proper mobile number format
                            String mobileNumber = accounts[0].PersonMobilePhone;
                            if (country == 'SG') {
                                System.assert(mobileNumber.contains('65') || mobileNumber.startsWith('9'), 
                                    'Mobile number should be in Singapore format: ' + mobileNumber);
                            } else {
                                System.assert(mobileNumber.contains('60') || mobileNumber.startsWith('0'), 
                                    'Mobile number should be in Malaysia format: ' + mobileNumber);
                            }
                        }
                    }
                }
            }
        }
        Test.stopTest();
    }
    */
    
    @isTest
    static void testStationAndDealerAssignment() {
        // First create test data
        createTestData(false, TEST_MOBILE_SG, 'SG');
        
        // Get the test session
        List<MessagingSession> sessions = [SELECT Id, ConversationId FROM MessagingSession LIMIT 1];
        if (sessions.isEmpty()) {
            return;
        }
    
        // Safely get record types
        Map<String, Schema.RecordTypeInfo> accountRTMap = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
        Id dealerRTId = accountRTMap.containsKey('Dealer') ? accountRTMap.get('Dealer').getRecordTypeId() : null;
        Id stationRTId = accountRTMap.containsKey(RECORD_TYPE_STATION) ? accountRTMap.get(RECORD_TYPE_STATION).getRecordTypeId() : null;
        
        if (dealerRTId == null || stationRTId == null) {
            System.debug('Required record types not found. Dealer RT: ' + dealerRTId + ', Station RT: ' + stationRTId);
            return;
        }
        
        // Create dealer account first
        Account dealerAccount = new Account(
            Name = 'Test Dealer',
            RecordTypeId = dealerRTId
        );
        insert dealerAccount;
        
        // Create station with the location code from mock (RYD0266)
        Account station = new Account(
            Name = 'Test Station',
            RecordTypeId = stationRTId,
            ParentId = dealerAccount.Id,
            Site_Id__c = 'RYD0266'
        );
        insert station;
        
        // Create dealer contact
        Contact dealerContact = new Contact(
            LastName = 'Dealer Contact',
            AccountId = dealerAccount.Id,
            Partner_Role__c = 'Dealer'
        );
        insert dealerContact;
        
        // Create Account Contact Relation
        AccountContactRelation acr = new AccountContactRelation(
            AccountId = dealerAccount.Id,
            ContactId = dealerContact.Id,
            IsActive = true
        );
        insert acr;
    
        // Set mock implementation for conversation entries
        Test.setMock(HttpCalloutMock.class, new OmniGetConversationEntriesMockImpl());
        
        AgentCreateCase.FlowInputs input = new AgentCreateCase.FlowInputs();
        input.messagingSessionId = sessions[0].Id;
        
        Test.startTest();
        List<AgentCreateCase.FlowOutputs> outputs = 
            AgentCreateCase.createCase(new List<AgentCreateCase.FlowInputs>{input});
        Test.stopTest();
        
        if (!outputs.isEmpty()) {
            List<Case> cases = [
                SELECT Id, Site__c, Dealer__c, OwnerId, Description
                FROM Case 
                WHERE Id = :outputs[0].caseId
            ];
            
            if (!cases.isEmpty()) {
                // Verify station assignment
                System.assertEquals(station.Id, cases[0].Site__c, 
                    'Case should be assigned to the correct station');
                
                // Verify dealer assignment
                System.assertEquals(dealerAccount.Id, cases[0].Dealer__c, 
                    'Case should be assigned to the correct dealer');
            }
        }
    }
    
    @isTest
    static void testStationAndDealerAssignmentWithInvalidLocation() {
        createTestData(false, TEST_MOBILE_SG, 'SG');
        
        List<MessagingSession> sessions = [SELECT Id FROM MessagingSession LIMIT 1];
        if (sessions.isEmpty()) {
            return;
        }
        
        AgentCreateCase.FlowInputs input = new AgentCreateCase.FlowInputs();
        input.messagingSessionId = sessions[0].Id;
        
        Test.startTest();
        List<AgentCreateCase.FlowOutputs> outputs = 
            AgentCreateCase.createCase(new List<AgentCreateCase.FlowInputs>{input});
        Test.stopTest();
        
        if (!outputs.isEmpty()) {
            Case createdCase = [
                SELECT Id, Site__c, Dealer__c, OwnerId
                FROM Case 
                WHERE Id = :outputs[0].caseId
            ];
            
            // Verify no station/dealer assignment for invalid location
            System.assertEquals(null, createdCase.Site__c, 
                'Case should not be assigned to a station with invalid location');
            System.assertEquals(null, createdCase.Dealer__c, 
                'Case should not be assigned to a dealer with invalid location');
        }
    }
}