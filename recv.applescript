--=====================================
-- This script is for iMessage Sender Client
-- The script should be placed into crontab
-- Most of configuration is read from database
-- Few of them is read from configuration files
-- 
-- Author: Kylin Huang
-- Version: 1.0.x
--=====================================


--=====================================
-- Global Constants
--=====================================
global recvVersion, clientId, mysql, sqlite
global settings, network

set recvVersion to "10000" as string
set clientId to do shell script "/bin/cat /Users/adways/Documents/id"
set mysql to "/usr/local/mysql/bin/mysql --defaults-extra-file=/Users/adways/Documents/my.cnf -N -e " as string
set sqlite to "/usr/bin/sqlite3 -html /Users/adways/Library/Messages/chat.db " as string
set network to "" as string

try
	if not checkIsRunning() then
		changeNetwork("Direct")
		if setLock() then
			if checkNewVersion() then
				upgradeClient()
			else
				set msgList to getMessagesReceived()
				setMessageReceived(msgList)
			end if
			clearLock()
		end if
	end if
end try

--=====================================
-- Sturcture
--=====================================
on make_associative_list()
	return {}
end make_associative_list

on find_record_for_key(the_assoc_list, the_key)
	try
		repeat with record_ref in the_assoc_list
			if the_key of record_ref is equal to the_key then return record_ref
		end repeat
	end try
	return missing value
end find_record_for_key

on get_associative_item(the_assoc_list, the_key)
	try
		set record_ref to find_record_for_key(the_assoc_list, the_key)
		if record_ref is equal to missing value then
			error "The key wasn't found." number -1728 from the_key
		end if
		return the_value of record_ref
	on error
		return missing value
	end try
end get_associative_item

on set_associative_item(the_assoc_list, the_key, the_value)
	try
		set record_ref to find_record_for_key(the_assoc_list, the_key)
		if record_ref is equal to missing value then
			set end of the_assoc_list to ¬
				{the_key:the_key, the_value:the_value}
		else
			set the_value of record_ref to the_value
		end if
		return
	end try
end set_associative_item

on trimStart(str)
	local str, whiteSpace
	try
		set str to str as string
		set whiteSpace to {character id 10, return, space, tab}
		try
			repeat while str's first character is in whiteSpace
				set str to str's text 2 thru -1
			end repeat
			return str
		on error number -1728
			return ""
		end try
	on error eMsg number eNum
		error "Can't trimStart: " & eMsg number eNum
	end try
end trimStart

--=====================================
-- System Operators
--=====================================

on setLock()
	try
		do shell script "/bin/ls /Users/adways/Documents/recv.lock"
		return false
	on error
		do shell script "/usr/bin/touch /Users/adways/Documents/recv.lock"
		do shell script "/bin/echo $PPID > /Users/adways/Documents/recv.pid"
		return true
	end try
end setLock

on clearLock()
	try
		do shell script "/bin/rm /Users/adways/Documents/recv.lock /Users/adways/Documents/recv.pid"
	end try
end clearLock

on checkIsRunning()
	try
		do shell script "/bin/ps -p `/bin/cat /Users/adways/Documents/recv.pid` > /dev/null"
		return true
	on error
		clearLock()
		return false
	end try
end checkIsRunning

on changeNetwork(location)
	try
		if network is not equal to location then
			do shell script "/usr/bin/sudo /usr/sbin/scselect " & location
			set network to location as string
			delay 3
		end if
	end try
end changeNetwork

--=====================================
-- DB Operators
--=====================================
on sendQuery(query, writeable)
	try
		set succ to false
		set dataRef to {}
		set quotedQuery to "\"SET interactive_timeout = 30; SET wait_timeout = 30; " & query & "\\G\""
		try
			set dbLines to paragraphs of (do shell script mysql & quotedQuery)
			set succ to true
		on error number 1
			if writeable then
				changeNetwork("75")
				do shell script mysql & quotedQuery
				changeNetwork("Direct")
				set succ to true
			end if
		end try
		if not writeable then
			set dataLine to {}
			repeat with dbLine in dbLines
				if (dbLine starts with "******") and (dbLine contains "row") then
					if (count dataLine) is greater than 0 then
						set dataRef to dataRef & {dataLine}
					end if
					set dataLine to {}
				else
					set dataLine to dataLine & dbLine
				end if
			end repeat
			if (count dataLine) is greater than 0 then
				set dataRef to dataRef & {dataLine}
			end if
		end if
	on error
		changeNetwork("Direct")
		set succ to false
	end try
	if writeable then
		return succ
	else
		return dataRef
	end if
end sendQuery

on loadSettings()
	try
		sendQuery("UPDATE sender SET version = '" & recvVersion & "' WHERE id = " & clientId, true)
		set dbRecords to sendQuery("SELECT setting_key, setting_value FROM settings WHERE type IN (1,6)", false)
		set settings to make_associative_list()
		repeat with l in dbRecords
			set_associative_item(settings, item 1 of l, item 2 of l)
		end repeat
	end try
end loadSettings

on getSettings(k)
	try
		return get_associative_item(settings, k)
	on error
		loadSettings()
		return missing value
	end try
end getSettings

on checkNewVersion()
	try
		loadSettings()
		set latestVersion to getSettings("recv_latest_version") as string
		if latestVersion is not equal to recvVersion then
			return true
		else
			return false
		end if
	on error
		return false
	end try
end checkNewVersion

on upgradeClient()
	try
		set clientURL to getSettings("recv_update_url") as string
		return downloadFile(clientURL, "/Users/adways/Documents/recv.scpt")
	on error
		return false
	end try
end upgradeClient

on setMessageReceived(msgList)
	repeat with msg in msgList
		set msgID to item 1 of msg as string
		set msgAccount to item 2 of msg as string
		set recvTime to item 3 of msg as string
		set msgContent to item 4 of msg as string
		sendQuery("INSERT INTO imessage_seed(sender_id, account, recv_time, content) VALUES (" & clientId & ", " & quoted form of msgAccount & ", " & quoted form of recvTime & "," & quoted form of msgContent & ")", true)
		try
			tell application "Messages" to decline chat id msgID
		end try
	end repeat
end setMessageReceived

--=====================================
-- SQLite Operators
--=====================================

on sendSQLiteQuery(query, writeable)
	set prevTIDs to text item delimiters of AppleScript
	try
		set succ to false
		
		set dataRef to {}
		set quotedQuery to "\"" & query & "\""
		set dbContent to (do shell script sqlite & quotedQuery)
		set succ to true
		if not writeable then
			set text item delimiters of AppleScript to "</TR>"
			set dbLines to text items of dbContent
			repeat with dbLine in dbLines
				if trimStart(dbLine) is not equal to "" then
					set dataLine to text 5 thru -1 of trimStart(dbLine)
					set text item delimiters of AppleScript to "</TD>"
					set dbFields to text items of dataLine
					set dataLine to {}
					repeat with dbField in dbFields
						if trimStart(dbField) is not equal to "" then
							set dataField to text 5 thru -1 of trimStart(dbField)
							set dataLine to dataLine & dataField
						end if
					end repeat
					set dataRef to dataRef & {dataLine}
				end if
			end repeat
		end if
	on error
		set succ to false
	end try
	set text item delimiters of AppleScript to prevTIDs
	if writeable then
		return succ
	else
		return dataRef
	end if
end sendSQLiteQuery

on getMessagesReceived()
	return sendSQLiteQuery("SELECT c.guid, REPLACE(c.chat_identifier,'+', '00') AS account, datetime(m.date + 978307200, 'unixepoch', 'localtime') AS recv_time, m.text FROM chat c JOIN chat_message_join cm ON c.rowid = cm.chat_id JOIN message m ON cm.message_id = m.rowid WHERE c.is_archived = 0 AND m.is_from_me = 0", false)
end getMessagesReceived
