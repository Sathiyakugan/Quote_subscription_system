import ballerina/http;
import ballerina/io;
import wso2/twitter;
import wso2/gmail;
import wso2/gsheets4;
import wso2/twilio;
import ballerina/config;
import ballerinax/docker;
import ballerina/log;
import ballerina/task;
import ballerina/runtime;
task:Timer? timer;


//Twitter API CONF

documentation{A valid Client id with twitter.}
string twitterClientId=config:getAsString("twitterClientId");

documentation{A valid Client Secret with twitter access.}
string twitterClientSecret=config:getAsString("twitterClientSecret");

documentation{A valid AccessToken.}
string twitterAccessToken=config:getAsString("twitterAccessToken");

documentation{A valid AccessTokenSecret.}
string twitterAccessTokenSecret=config:getAsString("twitterAccessTokenSecret");


//Gmail API CONF

documentation{A valid access token with gmail and google sheets access.}
string accessToken = config:getAsString("gmailAccessToken");

documentation{The client ID for your application.}
string clientId = config:getAsString("gmailClientId");

documentation{The client secret for your application.}
string clientSecret = config:getAsString("gmailClientSecret");

documentation{A valid refreshToken with gmail and google sheets access.}
string refreshToken = config:getAsString("gmailRefreshToken");


//Sender Details

documentation{Sender email address.}
string senderEmail = config:getAsString("SENDER");

documentation{The user's email address.}
string userId = config:getAsString("USER_ID");

//SpreadSheet API CONF

documentation{Spreadsheet id of the reference google sheet.}
string spreadsheetId = config:getAsString("SPREADSHEET_ID");

documentation{Sheet name of the reference googlle sheet.}
string sheetName = config:getAsString("SHEET_NAME");

//TWilio API CONF

documentation{Spreadsheet id of the reference google sheet.}
string TaccountSId = config:getAsString("TaccountSId");

documentation{Sheet name of the reference googlle sheet.}
string TauthToken = config:getAsString("TauthToken");



documentation{
    twitter client endpoint declaration with oAuth2 client configurations.
}

endpoint twitter:Client twitter {
    clientId: twitterClientId,
    clientSecret: twitterClientSecret,
    accessToken: twitterAccessToken,
    accessTokenSecret: twitterAccessTokenSecret
};


documentation{
    Gmail client endpoint declaration with oAuth2 client configurations.
}

endpoint gmail:Client gmailClient {
    clientConfig:{
        auth:{
            accessToken:accessToken,
            clientId:clientId,
            clientSecret:clientSecret,
            refreshToken:refreshToken
        }
    }
};


documentation{
    Google Sheets client endpoint declaration with http client configurations.
}

endpoint gsheets4:Client spreadsheetClient {
    clientConfig: {
        auth: {
            accessToken: accessToken,
            refreshToken: refreshToken,
            clientId: clientId,
            clientSecret: clientSecret
        }
    }
};


documentation{
    Google Sheets client endpoint declaration with http client configurations.
}

endpoint twilio:Client twilioEP {
    accountSId:TaccountSId,
    authToken:TauthToken,
    xAuthyKey:""
};



documentation{
       Schedule a timer task, which initially runs from now.
       After that, it runs every day.
       It will collect the tweets and process it and send it to the users
 }

function main(string... args) {

    (function() returns error?) onTriggerFunction = startService;
    function(error) onErrorFunction = cleanupError;
    timer = new task:Timer(startService,cleanupError,1000000, delay = 0);
    timer.start();
    runtime:sleep(30000);

}


function startService ()  {
    var tweetResponse = twitter->search ("quote");
    match tweetResponse {
        twitter:Status[] twitterStatus => {
            //Initial Text Out put of the Message
            io:println(twitterStatus);
            string textOut= "";
            string emailOut="";
            string mobileOut="Quote:: ";
            int i=0;
            foreach tweet in twitterStatus {

                if (((tweet["text"].contains("#quote")) ||(tweet["text"].contains("#quoteoftheday")) )){
                    textOut = textOut+ "#  "+tweet["text"]+ "\n\n";
                    emailOut=emailOut+"<P>"+tweet["text"]+"<P> <hr><br>";
                    var tweetResponseee = twitter->tweet(tweet["text"]);

                    if(i==0){
                        mobileOut=mobileOut+"#  "+tweet["text"];

                        if(!(mobileOut.length()>160)){
                            i++;
                        }

                    }
                }

            }
            sendNotification(emailOut,mobileOut);
        }
        twitter:TwitterError e => io:println(e);
    }
}


function cleanupError(error e) {
    io:print("[ERROR] cleanup failed");
}



documentation{
    Send notification to the customers.
}

function sendNotification(string emailOut,string mobileOut) {
    //Retrieve the customer details from spreadsheet.
    string[][] values = getCustomerDetailsFromGSheet();

    io:println(values);
    int i = 0;
    //Iterate through each customer details and send customized email.
    foreach value in values {
        //Skip the first row as it contains header values.
        if (i > 0) {
            string productName = value[0];
            string CutomerName = value[1];
            string customerEmail = value[2];
            string subject = "New tweet :: " + productName;

            io:println(subject);
            string phone ="+";

            try {
                if (value[3]!=null){
                    phone=phone+value[3];
                    sendmessage(phone,mobileOut);
                }
            } catch (error err) {
                io:println("No Number in that field: ", err.message);
            } finally {
                io:println("Finally block executed");
            }
            sendMail(customerEmail, subject,getCustomEmailTemplate(CutomerName, emailOut));
        }
        i = i + 1;
    }
}

documentation{
    Retrieves customer details from the spreadsheet statistics.

    R{{}} - Two dimensional string array of spreadsheet cell values.
}

function getCustomerDetailsFromGSheet() returns (string[][]) {
    //Read all the values from the sheet.
    string[][] values = check spreadsheetClient->getSheetValues(spreadsheetId, sheetName, "", "");
    log:printInfo("Retrieved customer details from spreadsheet id:" + spreadsheetId + " ;sheet name: "
            + sheetName);
    return values;
}


documentation{
    Send sms to the customers.
}


function sendmessage(string to,string message){
    var details = twilioEP->sendSms("+19727374715",to, message);
    match details {
        twilio:SmsResponse smsResponse => io:println(smsResponse);
        twilio:TwilioError twilioError => io:println(twilioError);
    }

}

documentation{
    Send mail to the customers.
}

function sendMail(string customerEmail, string subject, string messageBody) {
    //Create html message
    gmail:MessageRequest messageRequest;
    messageRequest.recipient = customerEmail;
    messageRequest.sender = senderEmail;
    messageRequest.subject = subject;
    messageRequest.messageBody = messageBody;
    messageRequest.contentType = gmail:TEXT_HTML;

    //Send mail
    var sendMessageResponse = gmailClient->sendMessage(userId, untaint messageRequest);
    string messageId;
    string threadId;
    match sendMessageResponse {
        (string, string) sendStatus => {
            (messageId, threadId) = sendStatus;
            log:printInfo("Sent email to " + customerEmail + " with message Id: " + messageId + " and thread Id:"
                    + threadId);
        }
        gmail:GmailError e => log:printInfo(e.message);
    }
}


documentation{
    Get the customized email template.
}

function getCustomEmailTemplate(string customerName, string emailOut) returns (string) {
    string emailTemplate = "<h2> Hi " + customerName + " </h2>";
    emailTemplate = emailTemplate + "<h3> Here's some Quotes on Twitter! </h3>";
    emailTemplate = emailTemplate + emailOut;
    return emailTemplate;
}



