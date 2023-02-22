script "com.emilyelizabeth.library.libsmtp"

on extensionInitialize
   if the target is not me then pass extensionInitialize
   set the _ideoverride of me to true
   insert the script of me into back
end extensionInitialize


on extensionFinalize
   if the target is not me then pass extensionFinalize
   remove the script of me from back
end extensionFinalize

/**
Type: library

Title: libSMTP

Author: Emily Elizabeth

Version: 1.0.0

SVGIcon: 

Summary: SMTP library for LiveCode

Description:
SMTP library for LiveCode which is event based.

Tags: smtp
*/

--- public handlers
// SMTPSend
// SMTPDisconnect


--- callbacks
/**
Name: SMTPConnected

Type: message

Syntax: SMTPConnected <pParam1>, <pParam2>

Summary: TODO.

Parameters:
pParam1: TODO.

pParam2: TODO.

Example: TODO

Description: TODO

**/
// SMTPConnected
// SMTPRequestAuthenticationMethod()
// SMTPLoggedIn
// SMTPRequestSender()
// SMTPRequestRecipient()
// SMTPRequestDataLine()
// SMTPMessageSent
// SMTPDisconnected


--- contants used for socket timeouts
constant kTwoMinutes   = 120000
constant kThreeMinutes = 180000
constant kFiveMinutes  = 300000
constant kTenMinutes   = 600000


local sCallback
local sSMTPReply
local sCurrentCommand

/**
Syntax: SMTPConnect <pServerAddress>, <pServerPort>, <pUseSSL>, <pCallback>

Summary: Opens a connection to the server.

Parameters:
pServerAddress: The host name or IP address of the SMTP server.

pSserverPort: The port the server is listening on (usually 25, 465, 587).

pUseSSL: A boolean whether to use a secure connection or not.

pCallback: long id of the LiveCode object that is going to handle the callbacks from the library.

Example: SMTPConnect "smtp.example.org", 587, false, the long of stack "smtpCallbacks"

Description:
Use the <SMTPConnect> command to opens a connection to the server.

**/
on SMTPConnect pServerAddress, pServerPort, pUseSSL, pCallback
   local tSender
   
   put pServerAddress & ":" & pServerPort & "|libSMTP" into tSender
   put EMPTY into sSMTPReply[tSender]
   put "CONN" into sCurrentCommand[tSender]
   put pCallback into sCallback[tSender]
   
   if (pUseSSL) then
      open secure socket to tSender with message "__libSMTPRead"
   else
      open socket to tSender with message "__libSMTPRead"
   end if
end SMTPConnect


on SMTPDisconnect pSender
   __libSMTPWrite pSender, "QUIT", kFiveMinutes
end SMTPDisconnect


on SMTPSend pSender
   dispatch function "SMTPRequestSender" to sCallback[pSender] with pSender
   
   if (the result is not EMPTY) then
      __libSMTPWrite pSender, "MAIL FROM:<" & the result & ">", kFiveMinutes
   end if
end SMTPSend


on __libSMTPRead pSender
   read from socket pSender until CRLF with message "__libSMTPGotData"
end __libSMTPRead


on __libSMTPGotData pSender, pData
   local tAuthMethods
   
   put pData after sSMTPReply[pSender]
   
   if (char 4 of pData = "-") then  // multi-line reply
      read from socket pSender until CRLF with message "__libSMTPGotData"
   else
      switch (char 1 to 3 of sSMTPReply[pSender])
         
         case 220  // <domain> service ready
            dispatch "SMTPConnected" to sCallback[pSender] with pSender, sSMTPReply[pSender]
            __libSMTPWrite pSender, "EHLO" && hostAddress(pSender), kFiveMinutes
            break
            
         case 221  // <domain> service closing transmission channel
            close socket pSender
            dispatch "SMTPDisconnected" to sCallback[pSender] with pSender
            break
            
         case 235  // password successful
            dispatch "SMTPLoggedIn" to sCallback[pSender] with pSender
            break
            
         case 250  // requested mail action okay, completed
            switch
               case (sCurrentCommand[pSender] = "EHLO")                  
                  put __libSMTPFindAuthMethods(sSMTPReply[pSender]) into tAuthMethods
                  
                  if (tAuthMethods is not EMPTY) then
                     dispatch function "SMTPRequestAuthenticationMethod" to sCallback[pSender] with pSender, tAuthMethods
                     
                     if (the result = FALSE) then
                        dispatch "SMTPLoggedIn" to sCallback[pSender] with pSender
                     else
                        __libSMTPWrite pSender, "AUTH" && the result, kFiveMinutes
                     end if
                  end if
                  break
                  
               case (sCurrentCommand[pSender] = "MAIL") 
                  __libSMTPGetNextRecipient pSender
                  break
                  
               case (sCurrentCommand[pSender] = "RCPT")
                  __libSMTPGetNextRecipient pSender
                  break
                  
               case (sCurrentCommand[pSender] = ".")
                  dispatch "SMTPMessageSent" to sCallback[pSender] with pSender
                  break
            end switch
            break
            
         case 251
            if (sCurrentCommand[pSender] = "RCPT") then
               dispatch "SMTPInvalidRecipient" to sCallback[pSender] with pSender
               __libSMTPGetNextRecipient pSender
            end if
            break
            
         case 354  // start mail input; end with <CRLF>.<CRLF>
            if (sCurrentCommand[pSender] = "DATA") then
               __libSMTPGetNextDataLine pSender
            end if
            break
            
         case 554  // transaction failed
            dispatch "SMTPError" to sCallback[pSender] with pSender, sSMTPReply[pSender]
            break
            
         default
            -- put sSMTPReply[pSender]
            close socket (line 1 of the openSockets)
      end switch
   end if
end __libSMTPGotData


on __libSMTPWrite pSender, data, timeout
   put EMPTY into sSMTPReply[pSender]
   put word 1 of data into sCurrentCommand[pSender]
   set the socketTimeoutInterval to timeout
   write data & CRLF to socket pSender with message "__libSMTPRead"
end __libSMTPWrite


on __libSMTPWriteDataLine sender, data, timeout
   set the socketTimeoutInterval to timeout
   if (data = ".") then
      write ".." & CRLF to socket sender with message "__libSMTPGetNextDataLine"
   else
      write data & CRLF to socket sender with message "__libSMTPGetNextDataLine"
   end if
end __libSMTPWriteDataLine


on __libSMTPGetNextDataLine sender
   dispatch function "SMTPRequestDataLine" to sCallback[sender] with sender
   if (the result is FALSE) then
      __libSMTPWrite sender, ".", kTenMinutes
   else
      __libSMTPWriteDataLine sender, the result, kThreeMinutes
   end if
end __libSMTPGetNextDataLine


on __libSMTPGetNextRecipient sender
   dispatch function "SMTPRequestRecipient" to sCallback[sender] with sender
   if (the result is FALSE) then
      __libSMTPWrite sender, "DATA", kTwoMinutes
   else
      __libSMTPWrite sender, "RCPT TO:<" & the result & ">", kFiveMinutes
   end if
end __libSMTPGetNextRecipient
   
   
private function __libSMTPFindAuthMethods data
   local results
   repeat for each line tLine in data
      if (word 1 of tLine = "250-AUTH") then
         put word 2 to -1 of tLine into results
         exit repeat
      else if (word 2 of tLine = "AUTH") then
         put word 3 to -1 of tLine into results
         exit repeat
      end if
   end repeat
   return results
end __libSMTPFindAuthMethods


on socketError sender, errorString
   dispatch "SMTPError" to sCallback[sender] with sender, errorString
end socketError


on socketTimeout sender
   dispatch "SMTPSocketTimeout" to sCallback[sender] with sender
end socketTimeout
