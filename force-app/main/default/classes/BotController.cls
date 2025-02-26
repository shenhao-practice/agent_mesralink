public class BotController {
    
    @InvocableMethod(label='Get Contact Details')
    public static List<TranscriptOutput> getContactData(List<TranscriptInput> transcript) {
        TranscriptOutput output = new TranscriptOutput();
        output.contactName = transcript[0].inputName;
        return new List<TranscriptOutput>{output};
    }
    
    
    public class TranscriptInput {        
        @InvocableVariable
        public String inputName;    
    }
    
    public class TranscriptOutput {
        @InvocableVariable
        public String contactName; 
    }
}