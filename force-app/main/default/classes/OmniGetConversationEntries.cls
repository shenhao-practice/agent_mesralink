/*
    Apex class to retrieve ConversationEntries from Connect API

    Created by: Jeff Lim (SFDC)
    Created date: 2024-04-12
*/
public with sharing class OmniGetConversationEntries {
    public OmniGetConversationEntries() {
        // void
    }

    // Method to retrieve Conversation Entries by Conversation ID
    public Map<Long, OmniConversationEntries.ConversationEntry> getConversationEntriesByConvId(String conversationId, String filterMsgRole) {
        List<Conversation> convs = [select ConversationIdentifier from Conversation where Id = :conversationId];
        if (convs.size()>0) {
            String conversationIdentifier = convs[0].conversationIdentifier;
            System.debug('conversationIdentifier: '+conversationIdentifier);
            return getConversationEntries(conversationIdentifier, filterMsgRole);
        } else {
            return new Map<Long, OmniConversationEntries.ConversationEntry>();
        }
    }

    // Method to retrieve Conversation Entries by Conversation Identifier
    public Map<Long, OmniConversationEntries.ConversationEntry> getConversationEntries(String conversationIdentifier, String filterMsgRole) {
        return getConversationEntries(conversationIdentifier, filterMsgRole, 50);
    }

    // Method to retrieve Conversation Entries by Conversation Identifier
    public Map<Long, OmniConversationEntries.ConversationEntry> getConversationEntries(String conversationIdentifier, String filterMsgRole, Integer recordLimit) {
        if (recordLimit==null) {
            recordLimit = 50;
        }

        HttpRequest httpRequest = new HttpRequest();  
        httpRequest.setMethod('GET');
        httpRequest.setEndpoint('callout:PDB_Messaging_NC/services/data/v62.0/connect/conversation/'+conversationIdentifier+'/entries?recordLimit='+EncodingUtil.urlEncode(String.valueOf(recordLimit),'UTF-8'));
        
        String response = '';
        Map<Long, OmniConversationEntries.ConversationEntry> mapConvEntries = new Map<Long, OmniConversationEntries.ConversationEntry>();
        try {  
            Http http = new Http();   
            HttpResponse httpResponse = http.send(httpRequest);  
            if (httpResponse.getStatusCode() == 200 ) {  
                response = JSON.serializePretty( JSON.deserializeUntyped(httpResponse.getBody()) );  

                OmniConversationEntries ces = OmniConversationEntries.parse(response);

                Long decCheck = long.valueOf('10000000000');
                if (ces!=null && ces.conversationEntries.size()>0) {
                    for (OmniConversationEntries.ConversationEntry ce: ces.conversationEntries) {
                        if (!String.isBlank(ce.messageText)) {
                            ce.messageText = ce.messageText.unescapeHtml4();
                        }
                        if (ce.clientTimestamp < decCheck) {
                            ce.clientTimestamp = ce.clientTimestamp * 1000;
                        }

                        ce.clientDatetime = convertLongToDatetime(ce.clientTimestamp);
                        ce.serverDatetime = convertLongToDatetime(ce.serverReceivedTimestamp);

                        // Filter message by role
                        if (filterMsgRole=='EndUser' && ce.sender.role==filterMsgRole) {
                            mapConvEntries.put(ce.clientTimestamp, ce);
                        } else if (filterMsgRole=='Chatbot' && ce.sender.role==filterMsgRole) {
                            mapConvEntries.put(ce.clientTimestamp, ce);
                        } else if (filterMsgRole=='' || filterMsgRole==null || filterMsgRole=='*') {
                            mapConvEntries.put(ce.clientTimestamp, ce);
                        }
                    }
                }

            } else if (httpResponse.getStatusCode() == 401 ) {
                System.debug(' httpResponse ' + httpResponse.getBody() );
                throw new CalloutException( httpResponse.getBody() );
            } else {
                System.debug(' httpResponse ' + httpResponse.getBody() );  
                throw new CalloutException( httpResponse.getBody() );  
            }   
        } catch( System.Exception e) {  
            System.debug('ERROR: '+ e);  
            throw e;  
        }  
        
        //Sort before return
        Map<Long, OmniConversationEntries.ConversationEntry> sortConvEntries = new Map<Long, OmniConversationEntries.ConversationEntry>();
        if (mapConvEntries.size()>0) {
            for (Long clientTimestamp: getSortedKeyset(mapConvEntries)) {
                //System.debug('Result clientTimestamp: '+clientTimestamp);
                sortConvEntries.put(clientTimestamp, mapConvEntries.get(clientTimestamp));
            }
        }
        
        return sortConvEntries;
        
    }

    // Method to convert timestamp value from Long to DateTime
    public DateTime convertLongToDatetime(Long timestamp) {
        DateTime gmtDatetime = DateTime.newInstance(timestamp);
        System.TimeZone myTz = UserInfo.getTimeZone();
        Integer millisecondOffsetGmt = myTz.getOffset(gmtDateTime);
        DateTime localDatetime = DateTime.newInstance(timeStamp + millisecondOffsetGmt);

        //System.debug(gmtDatetime);
        //System.debug(localDatetime);

        return localDatetime;
    }

    // Method to sort Conversation Entries in ascending order
    public List<Long> getSortedKeyset(Map<Long, OmniConversationEntries.ConversationEntry> dataMap) {
        List<Long> keySetList = new List<Long>();
        keySetList.addAll(dataMap.keySet());
        keySetList.sort();
        return keySetList;
    }

}