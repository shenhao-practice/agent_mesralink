/*
    Test class for OmniGetConversationEntries
    SeeAllData=True due to Conversation and Messaging Session data cannot prepare from test script
    - Suggest to have ready data in destination sandbox before executing test class

    Created by: Jeff Lim (SFDC)
    Created date: 2024-04-12
*/
@isTest(SeeAllData=True)
private class OmniGetConversationEntries_Test {

    @isTest static void testGetConversationEntriesByConversationIdentifier() {
        // Set mock callout class 
        Test.setMock(HttpCalloutMock.class, new OmniGetConversationEntriesMockImpl());
        
        // Call method to test.
        // This causes a fake response to be sent
        // from the class that implements HttpCalloutMock. 
        OmniGetConversationEntries ce = new OmniGetConversationEntries();
        Map<Long, OmniConversationEntries.ConversationEntry> res = ce.getConversationEntries('111', '*');
        
        System.debug('res: '+res);
        System.Assert(res!=null && res.size()>0, 'Cannot get conversation entries from Connect API!');
    }

    @isTest static void testGetConversationEntriesByConversationId() {
        // Set mock callout class 
        Test.setMock(HttpCalloutMock.class, new OmniGetConversationEntriesMockImpl());

        List<Conversation> convs = [select Id from Conversation limit 1];

        if (convs.size()>0) {
            // Call method to test.
            // This causes a fake response to be sent
            // from the class that implements HttpCalloutMock. 
            OmniGetConversationEntries ce = new OmniGetConversationEntries();
            Map<Long, OmniConversationEntries.ConversationEntry> res = ce.getConversationEntriesByConvId(convs[0].Id, '*');
            
            System.debug('res: '+res);
            System.Assert(res!=null && res.size()>0, 'Cannot get conversation entries from Connect API!');
        } else {
            //System.Assert(false, 'Cannot get Conversation ID!');
        }
    }

    @isTest static void testGetConversationEntriesByConversationIdentifier_Negative() {
        // Set mock callout class 
        Test.setMock(HttpCalloutMock.class, new OmniGetConversationEntriesMockError());
        
        // Call method to test.
        // This causes a fake response to be sent
        // from the class that implements HttpCalloutMock. 
        
        try {
            OmniGetConversationEntries ce = new OmniGetConversationEntries();
            Map<Long, OmniConversationEntries.ConversationEntry> res = ce.getConversationEntries('111', '*');

            System.Assert(false, 'Callout Error shall not pass!');
        } catch (Exception e) {
            System.Assert(true, 'Cannot get conversation entries from Connect API!');
        }
        
        
    }
}