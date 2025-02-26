@IsTest
public class BotController_Test {
    
    @IsTest
    static void testGetContactData() {
        // Arrange
        String testName = 'John Doe';
        BotController.TranscriptInput input = new BotController.TranscriptInput();
        input.inputName = testName;
        List<BotController.TranscriptInput> inputList = new List<BotController.TranscriptInput>{input};
        
        // Act
        Test.startTest();
        List<BotController.TranscriptOutput> result = BotController.getContactData(inputList);
        Test.stopTest();
        
        // Assert
        System.assertEquals(1, result.size(), 'Should return exactly one output record');
        System.assertEquals(testName, result[0].contactName, 'Contact name should match input name');
    }
    
    @IsTest
    static void testGetContactDataWithEmptyInput() {
        // Arrange
        BotController.TranscriptInput input = new BotController.TranscriptInput();
        List<BotController.TranscriptInput> inputList = new List<BotController.TranscriptInput>{input};
        
        // Act
        Test.startTest();
        List<BotController.TranscriptOutput> result = BotController.getContactData(inputList);
        Test.stopTest();
        
        // Assert
        System.assertEquals(1, result.size(), 'Should return exactly one output record');
        System.assertEquals(null, result[0].contactName, 'Contact name should be null for empty input');
    }
    
    @IsTest
    static void testTranscriptInputClass() {
        // Arrange & Act
        BotController.TranscriptInput input = new BotController.TranscriptInput();
        input.inputName = 'Test Name';
        
        // Assert
        System.assertEquals('Test Name', input.inputName, 'Input name should be set correctly');
    }
    
    @IsTest
    static void testTranscriptOutputClass() {
        // Arrange & Act
        BotController.TranscriptOutput output = new BotController.TranscriptOutput();
        output.contactName = 'Test Name';
        
        // Assert
        System.assertEquals('Test Name', output.contactName, 'Output name should be set correctly');
    }
}