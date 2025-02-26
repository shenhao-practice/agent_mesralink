@isTest
private class AgentUpdateMessagingSession_Test {
    private static Id channelId;
    
    @TestSetup
    static void setupTestData() {
        // First, create setup objects (MessagingChannel and Queue) in a separate transaction
        System.runAs(new User(Id = UserInfo.getUserId())) {
            String uniqueId = String.valueOf(Datetime.now().getTime());
            
            // Create MessagingChannel
            MessagingChannel channel = new MessagingChannel(
                DeveloperName = 'TestChannel_' + uniqueId,
                MasterLabel = 'Test Channel ' + uniqueId,
                MessageType = 'WhatsApp',
                IsActive = true,
                MessagingPlatformKey = 'whatsapp:+1234567890'
            );
            insert channel;
            
            // Create WhatsApp Queue
            Group whatsappQueue = new Group(
                Name = 'WhatsApp Queue ' + uniqueId,
                DeveloperName = 'WhatsApp_Queue_' + uniqueId.replaceAll('[^a-zA-Z0-9]', '_'),
                Type = 'Queue'
            );
            insert whatsappQueue;
            
            // Create Queue Members for the WhatsApp Queue
            QueueSobject queueSobject = new QueueSobject(
                QueueId = whatsappQueue.Id,
                SobjectType = 'MessagingSession'
            );
            insert queueSobject;
        }
    }
    
    // Helper method to create test data after setup
    private static void createTestData() {
        // Get the channel Id
        MessagingChannel channel = [SELECT Id FROM MessagingChannel WHERE DeveloperName LIKE 'TestChannel_%' ORDER BY CreatedDate DESC LIMIT 1];
        
        // Create MessagingEndUser with unique phone numbers for each test case
        List<MessagingEndUser> endUsers = new List<MessagingEndUser>();
        
        // Create two end users with unique platform keys
        for(Integer i = 0; i < 2; i++) {
            MessagingEndUser endUser = new MessagingEndUser(
                Name = 'Test End User ' + i,
                MessagingChannelId = channel.Id,
                MessageType = 'WhatsApp',
                MessagingPlatformKey = '+1234567' + String.valueOf(i).leftPad(3, '0')  // Creates unique numbers like +1234567000, +1234567001
            );
            endUsers.add(endUser);
        }
        insert endUsers;
        
        // Create test MessagingSession records
        List<MessagingSession> sessions = new List<MessagingSession>();
        
        // Create session for escalation test
        sessions.add(new MessagingSession(
            MessagingChannelId = channel.Id,
            MessagingEndUserId = endUsers[0].Id,
            Status = 'Active',
            Escalated_by_Agentforce__c = false
        ));
        
        // Create session for handled test
        sessions.add(new MessagingSession(
            MessagingChannelId = channel.Id,
            MessagingEndUserId = endUsers[1].Id,
            Status = 'Active',
            Handled_by_Agentforce__c = false
        ));
        
        insert sessions;
    }
    
    @isTest
    static void testEscalation() {
        createTestData();
        
        // Get test session
        MessagingSession testSession = [
            SELECT Id, Escalated_by_Agentforce__c 
            FROM MessagingSession 
            WHERE Escalated_by_Agentforce__c = false 
            LIMIT 1
        ];
        
        // Create input for the invocable method
        AgentUpdateMessagingSession.FlowInput input = new AgentUpdateMessagingSession.FlowInput();
        input.messagingSessionId = testSession.Id;
        input.functionName = 'Escalated by Agentforce';
        
        Test.startTest();
        List<AgentUpdateMessagingSession.FlowOutput> outputs = 
            AgentUpdateMessagingSession.processMessagingSession(new List<AgentUpdateMessagingSession.FlowInput>{input});
        Test.stopTest();
        
        // Verify results
        MessagingSession updatedSession = [
            SELECT Escalated_by_Agentforce__c 
            FROM MessagingSession 
            WHERE Id = :testSession.Id
        ];
        System.assertEquals(true, updatedSession.Escalated_by_Agentforce__c, 
            'Escalated_by_Agentforce__c should be true');
        System.assertEquals(true, outputs[0].status, 'Output status should be true');
    }
    
    @isTest
    static void testHandled() {
        createTestData();
        
        // Get test session
        MessagingSession testSession = [
            SELECT Id, Handled_by_Agentforce__c 
            FROM MessagingSession 
            WHERE Handled_by_Agentforce__c = false 
            LIMIT 1
        ];
        
        // Create input for the invocable method
        AgentUpdateMessagingSession.FlowInput input = new AgentUpdateMessagingSession.FlowInput();
        input.messagingSessionId = testSession.Id;
        input.functionName = 'Handled by Agentforce';
        
        Test.startTest();
        List<AgentUpdateMessagingSession.FlowOutput> outputs = 
            AgentUpdateMessagingSession.processMessagingSession(new List<AgentUpdateMessagingSession.FlowInput>{input});
        Test.stopTest();
        
        // Verify results
        MessagingSession updatedSession = [
            SELECT Handled_by_Agentforce__c 
            FROM MessagingSession 
            WHERE Id = :testSession.Id
        ];
        System.assertEquals(true, updatedSession.Handled_by_Agentforce__c, 
            'Handled_by_Agentforce__c should be true');
        System.assertEquals(true, outputs[0].status, 'Output status should be true');
    }
    
    @isTest
    static void testEmptyInput() {
        Test.startTest();
        List<AgentUpdateMessagingSession.FlowOutput> outputs = 
            AgentUpdateMessagingSession.processMessagingSession(new List<AgentUpdateMessagingSession.FlowInput>());
        Test.stopTest();
        
        System.assertEquals(false, outputs[0].status, 'Output status should be false for empty input');
    }
    
    @isTest
    static void testNullInput() {
        Test.startTest();
        List<AgentUpdateMessagingSession.FlowOutput> outputs = 
            AgentUpdateMessagingSession.processMessagingSession(null);
        Test.stopTest();
        
        System.assertEquals(false, outputs[0].status, 'Output status should be false for null input');
    }
    
	@isTest
    static void testEscalationWithException() {
        createTestData();
        
        // Get test session
        MessagingSession testSession = [
            SELECT Id, Escalated_by_Agentforce__c, Status
            FROM MessagingSession 
            WHERE Escalated_by_Agentforce__c = false 
            LIMIT 1
        ];
        
        // Create input for the invocable method
        AgentUpdateMessagingSession.FlowInput input = new AgentUpdateMessagingSession.FlowInput();
        input.messagingSessionId = testSession.Id;
        input.functionName = 'Escalated by Agentforce';
        
        Test.startTest();
        // Force a lock exception by updating in parallel
        MessagingSession lockSession = new MessagingSession(
            Id = testSession.Id,
            Status = 'Ended'  // Change status to simulate concurrent modification
        );
        
        // Run in parallel to force lock/concurrent update issue
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update lockSession;
        }
        
        List<AgentUpdateMessagingSession.FlowOutput> outputs = 
            AgentUpdateMessagingSession.processMessagingSession(new List<AgentUpdateMessagingSession.FlowInput>{input});
        Test.stopTest();
        
        // Verify results - the update should have succeeded despite the concurrent modification
        System.assertEquals(true, outputs[0].status, 'Output status should be true even with concurrent modification');
    }
    
    @isTest
    static void testHandledWithException() {
        createTestData();
        
        // Get test session
        MessagingSession testSession = [
            SELECT Id, Handled_by_Agentforce__c, Status
            FROM MessagingSession 
            WHERE Handled_by_Agentforce__c = false 
            LIMIT 1
        ];
        
        // Create input for the invocable method
        AgentUpdateMessagingSession.FlowInput input = new AgentUpdateMessagingSession.FlowInput();
        input.messagingSessionId = testSession.Id;
        input.functionName = 'Handled by Agentforce';
        
        Test.startTest();
        // Force a lock exception by updating in parallel
        MessagingSession lockSession = new MessagingSession(
            Id = testSession.Id,
            Status = 'Ended'  // Change status to simulate concurrent modification
        );
        
        // Run in parallel to force lock/concurrent update issue
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update lockSession;
        }
        
        List<AgentUpdateMessagingSession.FlowOutput> outputs = 
            AgentUpdateMessagingSession.processMessagingSession(new List<AgentUpdateMessagingSession.FlowInput>{input});
        Test.stopTest();
        
        // Verify results - the update should have succeeded despite the concurrent modification
        System.assertEquals(true, outputs[0].status, 'Output status should be true even with concurrent modification');
    }
    
    @isTest
    static void testInvalidFunctionName() {
        createTestData();
        
        // Get test session
        MessagingSession testSession = [
            SELECT Id 
            FROM MessagingSession 
            LIMIT 1
        ];
        
        // Create input with invalid function name
        AgentUpdateMessagingSession.FlowInput input = new AgentUpdateMessagingSession.FlowInput();
        input.messagingSessionId = testSession.Id;
        input.functionName = 'Invalid Function Name';
        
        Test.startTest();
        List<AgentUpdateMessagingSession.FlowOutput> outputs = 
            AgentUpdateMessagingSession.processMessagingSession(new List<AgentUpdateMessagingSession.FlowInput>{input});
        Test.stopTest();
        
        // Verify results
        System.assertEquals(false, outputs[0].status, 'Output status should be false for invalid function name');
    }
}