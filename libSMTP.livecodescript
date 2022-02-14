script "libSMTP"
--- public handlers
// SMTPConnect
// SMTPSend
// SMTPDisconnect


--- callbacks
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


on SMTPConnect serverAddress, serverPort, useSSL, callback
   local sender
   put serverAddress & ":" & serverPort & "|libSMTP" into sender
   put EMPTY into sSMTPReply[sender]
   put "CONN" into sCurrentCommand[sender]
   put callback into sCallback[sender]
   if (useSSL) then
      open secure socket to sender with message "libSMTPRead"
   else
      open socket to sender with message "libSMTPRead"
   end if
end SMTPConnect


on SMTPDisconnect sender
   libSMTPWrite sender, "QUIT", kFiveMinutes
end SMTPDisconnect


on SMTPSend sender
   dispatch function "SMTPRequestSender" to sCallback[sender] with sender
   if (the result is not EMPTY) then
      libSMTPWrite sender, "MAIL FROM:<" & the result & ">", kFiveMinutes
   end if
end SMTPSend


on libSMTPRead sender
   read from socket sender until CRLF with message "libSMTPGotData"
end libSMTPRead


on libSMTPGotData sender, data
   put data after sSMTPReply[sender]
   if (char 4 of data = "-") then  // multi-line reply
      read from socket sender until CRLF with message "libSMTPGotData"
   else
      switch (char 1 to 3 of sSMTPReply[sender])
         case 220  // <domain> service ready
            dispatch "SMTPConnected" to sCallback[sender] with sender, sSMTPReply[sender]
            libSMTPWrite sender, "EHLO" && hostAddress(sender), kFiveMinutes
            break
         case 221  // <domain> service closing transmission channel
            close socket sender
            dispatch "SMTPDisconnected" to sCallback[sender] with sender
            break
         case 235  // password successful
            dispatch "SMTPLoggedIn" to sCallback[sender] with sender
            break
         case 250  // requested mail action okay, completed
            if (sCurrentCommand[sender] = "EHLO") then
               local authMethods
               put libSMTPFindAuthMethods(sSMTPReply[sender]) into authMethods
               dispatch function "SMTPRequestAuthenticationMethod" to sCallback[sender] with sender, authMethods
               libSMTPWrite sender, "AUTH" && the result, kFiveMinutes
            else if (sCurrentCommand[sender] = "MAIL") then
               libSMTPGetNextRecipient sender
            else if (sCurrentCommand[sender] = "RCPT") then
               libSMTPGetNextRecipient sender
            else if (sCurrentCommand[sender] = ".") then
               dispatch "SMTPMessageSent" to sCallback[sender] with sender
            end if
            break
         case 251
            if (sCurrentCommand[sender] = "RCPT") then
               dispatch "SMTPInvalidRecipient" to sCallback[sender] with sender
               libSMTPGetNextRecipient sender
            end if
            break
         case 354  // start mail input; end with <CRLF>.<CRLF>
            if (sCurrentCommand[sender] = "DATA") then
               libSMTPGetNextDataLine sender
            end if
            break
         case 554  // transaction failed
            dispatch "SMTPError" to sCallback[sender] with sender, sSMTPReply[sender]
            break
         default
            put sSMTPReply[sender]
            close socket (line 1 of the openSockets)
      end switch
   end if
end libSMTPGotData


on libSMTPWrite sender, data, timeout
   put EMPTY into sSMTPReply[sender]
   put word 1 of data into sCurrentCommand[sender]
   set the socketTimeoutInterval to timeout
   write data & CRLF to socket sender with message "libSMTPRead"
end libSMTPWrite


on libSMTPWriteDataLine sender, data, timeout
   set the socketTimeoutInterval to timeout
   if (data = ".") then
      write ".." & CRLF to socket sender with message "libSMTPGetNextDataLine"
   else
      write data & CRLF to socket sender with message "libSMTPGetNextDataLine"
   end if
end libSMTPWriteDataLine


on libSMTPGetNextDataLine sender
   dispatch function "SMTPRequestDataLine" to sCallback[sender] with sender
   if (the result is FALSE) then
      libSMTPWrite sender, ".", kTenMinutes
   else
      libSMTPWriteDataLine sender, the result, kThreeMinutes
   end if
end libSMTPGetNextDataLine


on libSMTPGetNextRecipient sender
   dispatch function "SMTPRequestRecipient" to sCallback[sender] with sender
   if (the result is FALSE) then
      libSMTPWrite sender, "DATA", kTwoMinutes
   else
      libSMTPWrite sender, "RCPT TO:<" & the result & ">", kFiveMinutes
   end if
end libSMTPGetNextRecipient
   
   
   function libSMTPFindAuthMethods data
   local results
   repeat for each line tLine in data
      if (word 1 of tLine = "250-AUTH") then
         put word 2 to -1 of tLine into results
      else if (word 2 of tLine = "AUTH") then
         put word 3 to -1 of tLine into results
      end if
   end repeat
   return results
end libSMTPFindAuthMethods
