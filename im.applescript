--=====================================
-- This script is for iMessage Sender Client
-- The script should be placed into crontab
-- Most of configuration is read from database
-- Few of them is read from configuration files
-- 
-- Author: Kylin Huang
-- Version: 2.0.x
--=====================================


--=====================================
-- Global Constants
--=====================================
global imVersion, clientId, mysql, sqlite
global settings, clientInfo, network
global checkTaskList, creditCount, uncreditTaskList
global sendTaskList, waitingSendList, allFailCount
global msgReadTimeout, msgActivateTimeout, msgOperateTimeout, msgLaunchTimeout
global msgWaitInWindow, msgWaitSwitchWindow, msgWaitSwitchProc

set imVersion to "20011" as string
set clientId to do shell script "/bin/cat /Users/adways/Documents/id"
set mysql to "/usr/local/mysql/bin/mysql --defaults-extra-file=/Users/adways/Documents/my.cnf -N -e " as string
set sqlite to "/usr/bin/sqlite3 -html /Users/adways/Library/Messages/chat.db " as string
set network to "" as string

set checkTaskList to {}
set creditCount to 99999 as integer
set uncreditTaskList to {}
set sendTaskList to {}
set waitingSendList to {}
set allFailCount to 0

set {msgReadTimeout, msgActivateTimeout, msgOperateTimeout, msgLaunchTimeout} to {10, 10, 20, 30}
set {msgWaitInWindow, msgWaitSwitchWindow, msgWaitSwitchProc} to {2, 5, 10}

if not checkIsRunning() then
	changeNetwork("Direct")
	if setLock() then
		set {clientCommand, clientStatus} to getClientStatus()
		if clientStatus is equal to 0 then
			setClientStatus(1)
		end if
		if checkNewVersion() and (getSettings("client_force_update") as integer as boolean) then
			upgradeClient()
		else
			if clientStatus is equal to 5 then
				if clientCommand is equal to 0 then
					msgLogout(240)
				end if
			else
				if clientCommand is in {0, 1, 2, 3, 4, 5, 6, 8} then
					repeat
						set {clientCommand, clientStatus} to getClientStatus()
						if clientCommand is equal to 0 then
							if msgCheckStatusOnErrorClear(300) then
								waitSend(getSettings("client_sender_wait_time") as integer)
							else
								msgQuit(120)
							end if
							exit repeat
						else if clientCommand is equal to 1 then
							if msgCheckStatusOnErrorClear(300) then
								waitSend(getSettings("client_sender_wait_time") as integer)
								setClientStatus(2)
								if creditCount is greater than or equal to getSettings("client_checker_credit_count") as integer then
									if not checkCreditAccounts() then
										exit repeat
									end if
								end if
								checkAccounts()
							else
								setClientStatus(5)
								if getClientInfo("retry") is equal to 0 then
									msgLogout(240)
								else
									msgQuit(120)
								end if
							end if
						else if clientCommand is equal to 2 then
							if msgCheckStatusOnErrorClear(300) then
								setClientStatus(2)
								if allFailCount is greater than or equal to getSettings("client_sender_all_fail_count") as integer then
									setClientStatus(5)
									if getClientInfo("retry") is equal to 0 then
										msgLogout(240)
									else
										msgQuit(120)
									end if
									set allFailCount to 0 as integer
									exit repeat
								end if
								sendAccounts()
							else
								setClientStatus(5)
								if getClientInfo("retry") is equal to 0 then
									msgLogout(240)
								else
									msgQuit(120)
								end if
							end if
						else if clientCommand is equal to 3 then
							if msgQuit(120) then
								setClientStatus(2)
							else
								setClientStatus(3)
							end if
							exit repeat
						else if clientCommand is equal to 4 then
							setClientStatus(2)
							exit repeat
						else if clientCommand is equal to 5 then
							if clientStatus is in {0, 1} then
								if upgradeClient() then
									setClientStatus(2)
								else
									setClientStatus(3)
								end if
							end if
							exit repeat
						else if clientCommand is equal to 6 then
							if clientStatus is in {0, 1} then
								if doRemoteCommand() then
									setClientStatus(2)
								else
									setClientStatus(3)
								end if
							end if
							exit repeat
						else if clientCommand is equal to 8 then
							if clientStatus is in {0, 1} then
								if msgCheckStatusOnErrorClear(300) and msgLogout(240) then
									setClientStatus(5)
								end if
							end if
							exit repeat
						else
							exit repeat
						end if
					end repeat
					setSendTimeout(waitingSendList)
				else if clientCommand is equal to 7 then
					if clientStatus is in {0, 1} then
						if msgLogin(getSettings("client_login_timeout") as integer) then
							setClientStatus(2)
						else
							setClientStatus(5)
							msgLogout(240)
						end if
					end if
				else
					setClientStatus(5)
					msgLogout(240)
				end if
			end if
		end if
	end if
	set {clientCommand, clientStatus} to getClientStatus()
	if clientStatus is equal to 1 or (clientCommand is in {1, 2} and clientStatus is in {1, 2, 4}) then
		setClientStatus(0)
	end if
	clearLock()
end if

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

on joinList(aList, delimiter)
	try
		set retVal to ""
		set {prevDelimiter, AppleScript's text item delimiters} to {AppleScript's text item delimiters, delimiter}
		set retVal to aList as string
		set AppleScript's text item delimiters to prevDelimiter
		return retVal
	on error
		return ""
	end try
end joinList

on groupList(aList, groupLen)
	-- {"a", "b", "c", "d"}, 3 => {{"a", "b", "c"}, {"d"}}
	try
		if aList's class is not list then error "not a list." number -1704
		script k
			property l : aList
			property res : {}
		end script
		set tailLen to (count of k's l) mod groupLen
		repeat with idx from 1 to ((count of k's l) - tailLen) by groupLen
			set k's res's end to k's l's items idx thru (idx + groupLen - 1)
		end repeat
		if tailLen is not 0 then
			set k's res's end to k's l's items -tailLen thru -1
		end if
		return k's res
	on error errMsg number errNumber
		error "Can't groupList: " & errMsg number errNumber
	end try
end groupList

on replaceText(find, replace, subject)
	try
		set prevTIDs to text item delimiters of AppleScript
		set text item delimiters of AppleScript to find
		set subject to text items of subject
		
		set text item delimiters of AppleScript to replace
		set subject to "" & subject
		set text item delimiters of AppleScript to prevTIDs
		
		return subject
	on error
		return subject
	end try
end replaceText

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

on mapList(aList, columns)
	-- {{"a", "b"}, {"c", "d"}}, {1} => {{"a"}, {"c"}}
	try
		set rList to {}
		repeat with aLine in aList
			set rItem to {}
			if columns's class is integer then
				set rItem to item columns of aLine
			else if columns's class is list then
				repeat with columnId in columns
					set rItem to rItem & item columnId of aLine
				end repeat
			else
				return {}
			end if
			set rList to rList & {rItem}
		end repeat
		return rList
	on error
		return {}
	end try
end mapList

on unionList(aList, bList, aColumns, bColumns)
	-- {{"a", 1, "1"}, {"b", 2, "2"}}, {{"A", "z"}, {"B", "y"}}, {1, 2}, {1} => {{"a", 1, "A"}, {"b", 2, "B"}}
	try
		set rList to {}
		set i to 1
		repeat while i is less than or equal to (count aList)
			set rItem to {}
			repeat with columnId in aColumns
				set rItem to rItem & item columnId of item i of aList
			end repeat
			repeat with columnId in bColumns
				set rItem to rItem & item columnId of item i of bList
			end repeat
			set rList to rList & {rItem}
			set i to i + 1
		end repeat
		return rList
	on error
		return {}
	end try
end unionList

on pickList(aList, bList, aColumn, bColumn)
	-- {{"a", 1, "1"}, {"b", 2, "2"}, {"c", 3, "3"}}, {{"A", "1"}, {"C", "3"}, {"D", "4"}}, 3, 2 => {{"a", 1, "1"}, {"c", 3, "3"}}, {{"b", 2, "2"}}
	try
		set xList to {}
		set yList to {}
		repeat with aLine in aList
			set aKey to item aColumn of aLine
			set findSucc to false
			repeat with bLine in bList
				if item bColumn of bLine is equal to aKey then
					set findSucc to true
					set xList to xList & {aLine as list}
				end if
			end repeat
			if findSucc is equal to false then
				set yList to yList & {aLine as list}
			end if
		end repeat
		return {xList, yList}
	on error
		return {aList, {}}
	end try
end pickList

on listToAssociativeList(aList, keyColumn, valueColumns)
	-- {{"a", "b"}, {"c", "d"}}, 2, 1 => {{the_key:"b", the_value:{"a"}}, {the_key:"d", the_value:{"c"}}}
	try
		set rList to make_associative_list()
		repeat with aLine in aList
			if find_record_for_key(rList, item keyColumn of aLine) is equal to missing value then
				set_associative_item(rList, item keyColumn of aLine, {})
			end if
			set aItem to {}
			if valueColumns's class is integer then
				set aItem to item valueColumns of aLine
			else if valueColumns's class is list then
				repeat with columnId in valueColumns
					set aItem to aItem & item columnId of aLine
				end repeat
			end if
			set rItem to get_associative_item(rList, item keyColumn of aLine)
			set end of rItem to aItem
		end repeat
		return rList
	on error
		return {}
	end try
end listToAssociativeList

on joinReceiver(teleList)
	set receiverList to {}
	repeat with tele in teleList
		if "@" is in tele then
			set receiverList to receiverList & tele
		else if tele starts with "0081" then
			set receiverList to receiverList & ("+81" & text 5 thru -1 of tele)
		else if tele starts with "0086" then
			set receiverList to receiverList & ("+86" & text 5 thru -1 of tele)
		end if
	end repeat
	return joinList(receiverList, ", ")
end joinReceiver

--=====================================
-- System Operators
--=====================================
on setLock()
	try
		do shell script "/bin/ls /Users/adways/Documents/im.lock"
		return false
	on error
		do shell script "/usr/bin/touch /Users/adways/Documents/im.lock"
		do shell script "/bin/echo $PPID > /Users/adways/Documents/im.pid"
		return true
	end try
end setLock

on clearLock()
	try
		do shell script "/bin/rm /Users/adways/Documents/im.lock /Users/adways/Documents/im.pid"
	end try
end clearLock

on checkIsRunning()
	try
		do shell script "/bin/ps -p `/bin/cat /Users/adways/Documents/im.pid` > /dev/null"
		return true
	on error
		clearLock()
		return false
	end try
end checkIsRunning

on downloadFile(source, dest)
	local errMsg, errorNumber
	try
		do shell script "/bin/mv " & dest & " " & dest & ".bak"
		try
			do shell script "/usr/bin/curl " & source & " -o " & dest & " >/dev/null"
			do shell script "/bin/rm " & dest & ".bak"
			return true
		on error errMsg number errorNumber
			do shell script "/bin/mv " & dest & ".bak" & " " & dest
			setErrors(errorNumber, errMsg, "downloadFile")
			return false
		end try
	on error errMsg number errorNumber
		setErrors(errorNumber, errMsg, "downloadFile")
		return false
	end try
end downloadFile

on changeNetwork(location)
	try
		if network is not equal to location then
			do shell script "/usr/bin/sudo /usr/sbin/scselect " & location
			set network to location as string
			delay msgWaitSwitchProc
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
			changeNetwork("75")
			set dbLines to paragraphs of (do shell script mysql & quotedQuery)
			changeNetwork("Direct")
			set succ to true
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
		set dataRef to {}
	end try
	if writeable then
		return succ
	else
		return dataRef
	end if
end sendQuery

on loadSettings()
	try
		set dbRecords to sendQuery("SELECT setting_key, setting_value FROM settings WHERE type IN (1,4)", false)
		set settings to make_associative_list()
		repeat with l in dbRecords
			set_associative_item(settings, item 1 of l, item 2 of l)
		end repeat
		set debug_1 to get_associative_item(settings, "client_debug_1") as string
		if debug_1 is not equal to "" then
			set_associative_item(settings, debug_1, getClientInfo("debug1"))
		end if
		set debug_2 to get_associative_item(settings, "client_debug_2") as string
		if debug_2 is not equal to "" then
			set_associative_item(settings, debug_2, getClientInfo("debug2"))
		end if
		set debug_3 to get_associative_item(settings, "client_debug_3") as string
		if debug_3 is not equal to "" then
			set_associative_item(settings, debug_3, getClientInfo("debug3"))
		end if
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

on loadClientInfo()
	try
		set dbRecords to sendQuery("SELECT s.type, s.cmd_type, s.status, s.retry, s.command, s.version, a.account, a.passwd, s.debug, s.debug2, s.debug3 FROM sender s LEFT JOIN device_account l ON s.device_account_id = l.id LEFT JOIN account a ON l.account_id = a.id WHERE s.id = " & clientId, false)
		set clientInfo to make_associative_list()
		set_associative_item(clientInfo, "type", item 1 of item 1 of dbRecords as integer)
		set_associative_item(clientInfo, "cmd_type", item 2 of item 1 of dbRecords as integer)
		set_associative_item(clientInfo, "status", item 3 of item 1 of dbRecords as integer)
		set_associative_item(clientInfo, "retry", item 4 of item 1 of dbRecords as integer)
		set_associative_item(clientInfo, "command", item 5 of item 1 of dbRecords as string)
		if item 6 of item 1 of dbRecords is not equal to "NULL" then
			set_associative_item(clientInfo, "account", item 7 of item 1 of dbRecords as string)
		end if
		if item 7 of item 1 of dbRecords is not equal to "NULL" then
			set_associative_item(clientInfo, "password", item 8 of item 1 of dbRecords as string)
		end if
		set_associative_item(clientInfo, "debug1", item 9 of item 1 of dbRecords as real)
		set_associative_item(clientInfo, "debug2", item 10 of item 1 of dbRecords as integer)
		set_associative_item(clientInfo, "debug3", item 11 of item 1 of dbRecords as string)
		if item 6 of item 1 of dbRecords as string is not equal to imVersion then
			sendQuery("UPDATE sender SET version = '" & imVersion & "' WHERE id = " & clientId, true)
		end if
	end try
end loadClientInfo

on getClientInfo(k)
	try
		return get_associative_item(clientInfo, k)
	on error
		return missing value
	end try
end getClientInfo

on getClientStatus()
	try
		loadClientInfo()
		set clientCommand to getClientInfo("cmd_type") as integer
		set clientStatus to getClientInfo("status") as integer
		return {clientCommand, clientStatus}
	on error
		return {0, 0}
	end try
end getClientStatus

on setClientStatus(status)
	try
		set_associative_item(clientInfo, "status", status)
		return sendQuery("UPDATE sender SET version = '" & imVersion & "', status = " & status & ", last_action = CURRENT_TIMESTAMP  WHERE id = " & clientId, true)
	on error
		return false
	end try
end setClientStatus

on checkNewVersion()
	try
		loadSettings()
		set latestVersion to getSettings("client_latest_version") as string
		if latestVersion is not equal to imVersion then
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
		set clientURL to getSettings("client_update_url") as string
		return downloadFile(clientURL, "/Users/adways/Documents/im.scpt")
	on error
		return false
	end try
end upgradeClient

on doRemoteCommand()
	local errMsg, errorNumber
	try
		set command to getClientInfo("command") as string
		try
			do shell script command
			return true
		on error errMsg number errorNumber
			setErrors(errorNumber, errMsg, "doRemoteCommand")
			return false
		end try
	on error
		return false
	end try
end doRemoteCommand

on checkIsAllowSend()
	try
		set dbRecords to sendQuery("SELECT TIME_TO_SEC(NOW())", false)
		set currTime to item 1 of item 1 of dbRecords as integer
		set sendStart to getSettings("global_send_start") as integer
		set sendStop to getSettings("global_send_stop") as integer
		if currTime is greater than sendStart and currTime is less than sendStop then
			return true
		end if
		return false
	on error
		return false
	end try
end checkIsAllowSend

on getCheckTable()
	try
		set dbRecords to sendQuery("SELECT tablename FROM imessagetable WHERE type = 1 AND wait_num > unassign_num AND priority > 0 ORDER BY priority DESC, id ASC", false)
		return dbRecords
	on error
		return {}
	end try
end getCheckTable

on getSendTable()
	try
		set dbRecords to sendQuery("SELECT tablename FROM imessagetable WHERE type = 2 AND wait_num > unassign_num AND priority > 0 ORDER BY priority DESC, id ASC", false)
		return dbRecords
	on error
		return {}
	end try
end getSendTable

on getCheckTasks()
	-- table, id, account
	try
		set checkOnce to getSettings("client_checker_result_count") as integer
		set checkTables to getCheckTable()
		repeat with checkTable in checkTables
			set dbRecords to sendQuery("SELECT id, account FROM " & checkTable & " WHERE sender_id = " & clientId & " AND checked = 0 LIMIT " & checkOnce, false)
			repeat with i from 1 to (count dbRecords)
				set end of checkTaskList to {checkTable, item 1 of item i of dbRecords, item 2 of item i of dbRecords}
			end repeat
			if (count checkTaskList) is greater than or equal to checkOnce then
				exit repeat
			end if
		end repeat
	end try
end getCheckTasks

on getSendTasks()
	-- table, id, account, content
	try
		if not checkIsAllowSend() then
			return
		end if
		set sendOnce to getSettings("client_sender_result_count") as integer
		set sendTables to getSendTable()
		repeat with sendTable in sendTables
			set dbRecords to sendQuery("SELECT id, account, content FROM " & sendTable & " WHERE sender_id = " & clientId & " AND status = 0 LIMIT " & sendOnce, false)
			set idList to {}
			repeat with i from 1 to (count dbRecords)
				set end of sendTaskList to {sendTable, text item 1 of item i of dbRecords, text item 2 of item i of dbRecords, joinList(text items 3 thru -1 of item i of dbRecords, "
")}
				set idList to idList & text item 1 of item i of dbRecords
			end repeat
			sendQuery("UPDATE " & sendTable & " SET status = 3 WHERE sender_id = " & clientId & " AND id IN ('" & joinList(idList, "','") & "')", true)
			if (count sendTaskList) is greater than or equal to sendOnce then
				exit repeat
			end if
		end repeat
	end try
end getSendTasks

on getCreditTasks()
	try
		return sendQuery("(SELECT account, status FROM creditable_account WHERE status = 2 ORDER BY RAND() LIMIT 3) UNION (SELECT account, status FROM creditable_account WHERE status = 1 ORDER BY RAND() LIMIT 2) ORDER BY account", false)
	on error
		return {}
	end try
end getCreditTasks

on addUncreditTasks(teleList)
	repeat with tele in teleList
		set uncreditTaskList to uncreditTaskList & {tele as list}
	end repeat
end addUncreditTasks

on rollbackUncreditTasks()
	try
		if (count uncreditTaskList) is greater than 0 then
			set uncreditTableList to make_associative_list()
			repeat with i in uncreditTaskList
				if find_record_for_key(uncreditTableList, item 1 of i) is equal to missing value then
					set_associative_item(uncreditTableList, item 1 of i, {item 2 of i})
				else
					set t to get_associative_item(uncreditTableList, item 1 of i)
					set end of t to item 2 of i
				end if
			end repeat
			repeat with i in uncreditTableList
				set table to the_key of i
				set idList to the_value of i
				sendQuery("UPDATE " & table & " SET sender_id = 0, status = 0, checked = 0 WHERE sender_id = " & clientId & " AND id IN ('" & joinList(idList, "','") & "')", true)
			end repeat
			set uncreditTaskList to {}
		end if
	end try
end rollbackUncreditTasks

on commitUncreditTasks()
	set uncreditTaskList to {}
end commitUncreditTasks

on setCheckTaskResults(succList, failList)
	try
		set succNum to count succList
		set failNum to count failList
		if succNum is greater than 0 then
			set succTableList to listToAssociativeList(succList, 1, 2)
			repeat with sLine in succTableList
				set table to the_key of sLine
				set idList to the_value of sLine
				sendQuery("UPDATE " & table & " SET status = 1, failed = 0, checked = 1, last_check = CURRENT_TIMESTAMP WHERE id IN ('" & joinList(idList, "','") & "')", true)
			end repeat
		end if
		if failNum is greater than 0 then
			set failTableList to listToAssociativeList(failList, 1, 2)
			repeat with sLine in failTableList
				set table to the_key of sLine
				set idList to the_value of sLine
				sendQuery("UPDATE " & table & " SET status = 2, checked = 1, last_check = CURRENT_TIMESTAMP WHERE id IN ('" & joinList(idList, "','") & "')", true)
			end repeat
		end if
		sendQuery("INSERT INTO statistics(sender_id, date, cmd_type, succ_num, fail_num) VALUES (" & clientId & ", DATE(CURRENT_TIMESTAMP), 1, " & succNum & ", " & failNum & ") ON DUPLICATE KEY UPDATE succ_num = succ_num + " & succNum & ", fail_num = fail_num + " & failNum, true)
		sendQuery("UPDATE device_account i, sender s SET i.total_check = i.total_check + " & (succNum + failNum) & " WHERE i.id = s.device_account_id AND s.id = " & clientId, true)
	end try
end setCheckTaskResults

on setSendTaskResults(succList, failList)
	try
		set succNum to count succList
		set failNum to count failList
		if succNum is greater than 0 then
			set succTableList to listToAssociativeList(succList, 1, 2)
			repeat with sLine in succTableList
				set table to the_key of sLine
				set idList to the_value of sLine
				sendQuery("UPDATE " & table & " SET status = 1, send_time = CURRENT_TIMESTAMP WHERE id IN ('" & joinList(idList, "','") & "')", true)
			end repeat
		end if
		if failNum is greater than 0 then
			set failTableList to listToAssociativeList(failList, 1, 2)
			repeat with sLine in failTableList
				set table to the_key of sLine
				set idList to the_value of sLine
				sendQuery("UPDATE " & table & " SET status = 2 WHERE id IN ('" & joinList(idList, "','") & "')", true)
			end repeat
		end if
		sendQuery("INSERT INTO statistics(sender_id, date, cmd_type, succ_num, fail_num) VALUES (" & clientId & ", DATE(CURRENT_TIMESTAMP), 2, " & succNum & ", " & failNum & ") ON DUPLICATE KEY UPDATE succ_num = succ_num + " & succNum & ", fail_num = fail_num + " & failNum, true)
		sendQuery("UPDATE device_account i, sender s SET i.total_send = i.total_send + " & (succNum + failNum) & " WHERE i.id = s.device_account_id AND s.id = " & clientId, true)
	end try
end setSendTaskResults

on setErrors(errMsg, errNum, func)
	try
		return sendQuery("INSERT INTO errors(sender_id, version,err_num, err_msg, occured_func) VALUES(" & clientId & ", '" & imVersion & "', " & errNum & ", '" & replaceText("'", " ", errMsg) & "', '" & func & "')", true)
	end try
	return false
end setErrors

on setSendTimeout(timeoutList)
	try
		if (count timeoutList) is greater than 0 then
			set waitingTableList to make_associative_list()
			repeat with i in timeoutList
				if find_record_for_key(waitingTableList, item 1 of i) is equal to missing value then
					set_associative_item(waitingTableList, item 1 of i, {item 2 of i})
				else
					set t to get_associative_item(waitingTableList, item 1 of i)
					set end of t to item 2 of i
				end if
			end repeat
			repeat with i in waitingTableList
				set table to the_key of i
				set idList to the_value of i
				sendQuery("UPDATE " & table & " SET status = 3 WHERE sender_id = " & clientId & " AND id IN ('" & joinList(idList, "','") & "')", true)
			end repeat
			sendQuery("INSERT INTO statistics(sender_id, date, cmd_type, succ_num, fail_num) VALUES (" & clientId & ", DATE(CURRENT_TIMESTAMP), 2, 0, " & (count timeoutList) & ") ON DUPLICATE KEY UPDATE fail_num = fail_num + " & (count timeoutList), true)
			set timeoutList to {}
		end if
	end try
end setSendTimeout

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

on cleanDB()
	sendSQLiteQuery("DELETE FROM message", true)
	sendSQLiteQuery("DELETE FROM chat", true)
	sendSQLiteQuery("DELETE FROM attachment", true)
	sendSQLiteQuery("DELETE FROM handle", true)
	sendSQLiteQuery("DELETE FROM chat_handle_join", true)
	sendSQLiteQuery("DELETE FROM chat_message_join", true)
	sendSQLiteQuery("DELETE FROM message_attachment_join", true)
end cleanDB

on getAccountsDelivered()
	return sendSQLiteQuery("SELECT DISTINCT c.guid, REPLACE(c.chat_identifier,'+', '00') FROM chat c JOIN chat_message_join cm ON c.rowid = cm.chat_id JOIN message m ON cm.message_id = m.rowid WHERE c.is_archived = 0 AND m.is_from_me = 1 AND m.is_delivered = 1", false)
end getAccountsDelivered

on getAccountsWaiting()
	return sendSQLiteQuery("SELECT DISTINCT c.guid, REPLACE(c.chat_identifier,'+', '00') FROM chat c JOIN chat_message_join cm ON c.rowid = cm.chat_id JOIN message m ON cm.message_id = m.rowid WHERE c.is_archived = 0 AND m.is_from_me = 1 AND m.is_delivered = 0 AND m.is_sent = 1", false)
end getAccountsWaiting

on getAccountsWaitingTimeout(tmout)
	return sendSQLiteQuery("SELECT DISTINCT c.guid, REPLACE(c.chat_identifier,'+', '00') FROM chat c JOIN chat_message_join cm ON c.rowid = cm.chat_id JOIN message m ON cm.message_id = m.rowid WHERE c.is_archived = 0 AND m.is_from_me = 1 AND m.is_delivered = 0 AND m.is_sent = 1 AND JULIANDAY('NOW') * 86400 - JULIANDAY(m.date + 978307200, 'unixepoch') * 86400 > " & tmout, false)
end getAccountsWaitingTimeout

on getAccountsFailed()
	return sendSQLiteQuery("SELECT DISTINCT c.guid, REPLACE(c.chat_identifier,'+', '00') FROM chat c JOIN chat_message_join cm ON c.rowid = cm.chat_id JOIN message m ON cm.message_id = m.rowid WHERE c.is_archived = 0 AND m.is_from_me = 1 AND m.is_sent = 0", false)
end getAccountsFailed

--=====================================
-- UI operators
--=====================================

on msgDealWithNotification(tmout)
	-- 18 seconds
	set procStart to current date
	try
		with timeout of msgReadTimeout seconds
			tell application "System Events" to set isRunNotifier to (exists process "UserNotificationCenter")
		end timeout
		if isRunNotifier then
			with timeout of msgReadTimeout seconds
				tell application "System Events" to set windowNotifier to (count windows of process "UserNotificationCenter")
			end timeout
			set pw to getClientInfo("password") as string
			repeat while windowNotifier is greater than 0
				if (current date) - procStart is greater than tmout then
					return false
				end if
				with timeout of msgReadTimeout seconds
					tell application "System Events" to set buttonNum to (count buttons of window 1 of process "UserNotificationCenter")
				end timeout
				if buttonNum is equal to 1 then
					-- 别处登录
					with timeout of msgOperateTimeout seconds
						tell application "System Events" to click button 1 of window 1 of process "UserNotificationCenter"
					end timeout
				else if buttonNum is equal to 2 and pw is not equal to missing value then
					-- 密码框
					with timeout of msgActivateTimeout seconds
						activate application "UserNotificationCenter"
					end timeout
					with timeout of msgOperateTimeout seconds
						tell application "System Events"
							set value of text field 1 of window 1 of process "UserNotificationCenter" to pw
							click button 1 of window 1 of process "UserNotificationCenter"
						end tell
					end timeout
				else
					with timeout of msgActivateTimeout seconds
						activate application "UserNotificationCenter"
					end timeout
					with timeout of msgOperateTimeout seconds
						tell application "System Events" to click button 2 of window 1 of process "UserNotificationCenter"
						-- 取消
					end timeout
				end if
				delay msgWaitSwitchWindow
				with timeout of msgReadTimeout seconds
					tell application "System Events" to set windowNotifier to (count windows of process "UserNotificationCenter")
				end timeout
			end repeat
		end if
		return true
	on error
		return false
	end try
end msgDealWithNotification

on msgStartProc(tmout)
	-- 61 seconds
	set procStart to current date
	msgDealWithNotification(tmout)
	try
		with timeout of msgReadTimeout seconds
			tell application "System Events" to set isRunMessages to (exists process "Messages")
		end timeout
		if not isRunMessages then
			with timeout of msgLaunchTimeout seconds
				launch application "Messages"
			end timeout
			delay msgWaitSwitchProc
		end if
		with timeout of msgActivateTimeout seconds
			activate application "Messages"
		end timeout
		return true
	on error
		return false
	end try
end msgStartProc

on msgWindowStatus(tmout)
	-- 6 seconds
	set procStart to current date
	local errMsg, errorNumber
	set varWindowError to {"AXImage", "AXStaticText", "AXStaticText", "AXButton", "AXStaticText"}
	set varWindowAccount to {"AXButton", "AXButton", "AXButton", "AXToolbar", "AXGroup", "AXStaticText"}
	try
		with timeout of msgActivateTimeout seconds
			activate application "Messages"
		end timeout
		with timeout of msgReadTimeout seconds
			tell application "System Events" to set numWindows to count windows of process "Messages"
		end timeout
		if numWindows is equal to 0 then
			return "NotRun"
		else if numWindows is equal to 1 then
			with timeout of msgReadTimeout seconds
				tell application "System Events"
					set varWindow to window 1 of process "Messages"
					set windowArch to role of UI elements of varWindow
					set varWindowSubrole to subrole of varWindow
					set varWindowFocuesd to focused of varWindow
				end tell
			end timeout
			if varWindowSubrole is equal to "AXStandardWindow" then
				return "Main"
			else if varWindowSubrole is equal to "AXDialog" and varWindowFocuesd is equal to true and windowArch is equal to varWindowError then
				return "Error"
			else
				return "Unknown"
			end if
		else if numWindows is equal to 2 then
			with timeout of msgReadTimeout seconds
				tell application "System Events"
					set varWindow to window 1 of process "Messages"
					set windowArch to role of UI elements of varWindow
					set varWindowSubrole to subrole of varWindow
					set varWindowFocuesd to focused of varWindow
					set buttonName to name of button 1 of varWindow
				end tell
			end timeout
			if varWindowSubrole is equal to "AXStandardWindow" and windowArch is equal to varWindowAccount then
				return "Account"
			else if varWindowSubrole is equal to "AXDialog" and windowArch is equal to varWindowError and buttonName is equal to "好" then
				return "Send"
			else if varWindowSubrole is equal to "AXDialog" and varWindowFocuesd is equal to true and windowArch is equal to varWindowError then
				return "Error"
			else
				return "Unknown"
			end if
		else
			return "Unknown"
		end if
	on error errMsg number errorNumber
		if errorNumber is equal to -1728 then
			return "NotRun"
		else if errorNumber is equal to -1719 then
			delay msgWaitInWindow
			return msgWindowStatus(tmout - ((current date) - procStart))
		else
			setErrors(errMsg, errorNumber, "msgWindowStatus")
			error errMsg number errorNumber
		end if
	end try
end msgWindowStatus

on msgMainWindowStatus(tmout)
	-- 10 seconds
	set procStart to current date
	local errMsg, errorNumber
	set varMainAccount to {"AXButton", "AXButton", "AXGroup"}
	set varMainOneButton to {"AXImage", "AXStaticText", "AXStaticText", "AXButton"}
	set varMainTwoButton to {"AXImage", "AXStaticText", "AXStaticText", "AXButton", "AXButton"}
	try
		with timeout of msgActivateTimeout seconds
			activate application "Messages"
		end timeout
		with timeout of msgReadTimeout seconds
			tell application "System Events" to set numSheets to count sheets of window 1 of process "Messages"
		end timeout
		if numSheets is equal to 0 then
			return "Main"
		else if numSheets is equal to 1 then
			with timeout of msgReadTimeout seconds
				tell application "System Events"
					set varSheet to sheet 1 of window 1 of process "Messages"
					set sheetArch to role of UI elements of varSheet
					set buttonName to name of button 1 of varSheet
				end tell
			end timeout
			if sheetArch is equal to varMainOneButton and buttonName is equal to "好" then
				return "Send"
			else if sheetArch is equal to varMainTwoButton and buttonName is equal to "删除" then
				return "Delete"
			else if sheetArch is equal to varMainTwoButton and buttonName is equal to "登录" then
				return "AccountFail"
			else if sheetArch is equal to varMainAccount and buttonName is equal to "以后" then
				return "Account"
			else if sheetArch is equal to varMainAccount and buttonName is equal to "返回" then
				with timeout of msgReadTimeout seconds
					tell application "System Events" to set accountChecked to value of checkbox 1 of UI element 1 of row 1 of table 1 of scroll area 1 of group 1 of group 1 of group 1 of varSheet
				end timeout
				
				if accountChecked is equal to 1 then
					with timeout of msgOperateTimeout seconds
						tell application "System Events" to click button 2 of varSheet
					end timeout
					return "Main"
				else
					with timeout of msgOperateTimeout seconds
						tell application "System Events" to click button 1 of varSheet
					end timeout
					return "Account"
				end if
			else
				return "Unknown"
			end if
		else
			return "Unknown"
		end if
	on error errMsg number errorNumber
		if errorNumber is equal to -1719 then
			delay msgWaitInWindow
			return msgMainWindowStatus(tmout - ((current date) - procStart))
		else
			setErrors(errMsg, errorNumber, "msgMainWindowStatus")
			error errMsg number errorNumber
		end if
	end try
end msgMainWindowStatus

on msgAccountAccountStatus(tmout)
	-- 39 seconds
	set procStart to current date
	local errMsg, errorNumber
	try
		with timeout of msgActivateTimeout seconds
			activate application "Messages"
		end timeout
		with timeout of msgOperateTimeout seconds
			tell application "System Events" to click button 2 of tool bar 1 of window 1 of process "Messages"
		end timeout
		
		set lineIMessage to 1
		set lineBonjour to 2
		with timeout of msgReadTimeout seconds
			tell application "System Events" to set tagIMessage to name of static text 1 of UI element 1 of row lineIMessage of table 1 of scroll area 1 of group 1 of group 1 of window 1 of process "Messages"
		end timeout
		if tagIMessage is equal to "Bonjour" then
			set lineBonjour to 1
			set lineIMessage to 2
		end if
		
		with timeout of msgOperateTimeout seconds
			-- close Bonjour
			tell application "System Events"
				set selected of row lineBonjour of table 1 of scroll area 1 of group 1 of group 1 of window 1 of process "Messages" to true
				if value of checkbox 3 of group 1 of group 2 of group 1 of group 1 of window 1 of process "Messages" is equal to 1 then
					click checkbox 3 of group 1 of group 2 of group 1 of group 1 of window 1 of process "Messages"
				end if
				if value of checkbox 2 of group 1 of group 2 of group 1 of group 1 of window 1 of process "Messages" is equal to 1 then
					click checkbox 2 of group 1 of group 2 of group 1 of group 1 of window 1 of process "Messages"
				end if
			end tell
		end timeout
		
		with timeout of msgOperateTimeout seconds
			tell application "System Events" to set selected of row lineIMessage of table 1 of scroll area 1 of group 1 of group 1 of window 1 of process "Messages" to true
		end timeout
		with timeout of msgReadTimeout seconds
			tell application "System Events" to set statusIMessage to name of static text 2 of UI element 1 of row lineIMessage of table 1 of scroll area 1 of group 1 of group 1 of window 1 of process "Messages"
		end timeout
		if statusIMessage is equal to "iMessage" then
			-- Account Status
			with timeout of msgReadTimeout seconds
				tell application "System Events"
					set statusAccount to value of checkbox 2 of group 1 of group 2 of group 1 of group 1 of window 1 of process "Messages"
					set statusAccountEnable to enabled of checkbox 2 of group 1 of group 2 of group 1 of group 1 of window 1 of process "Messages"
				end tell
			end timeout
			if statusAccount is equal to 1 and statusAccountEnable is equal to true then
				return true
			end if
		else
			-- No login
			return false
		end if
	on error errMsg number errorNumber
		if errorNumber is equal to -1719 then
			return msgAccountStatus(tmout - ((current date) - procStart))
		else
			setErrors(errMsg, errorNumber, "msgAccountAccountStatus")
			error errMsg number errorNumber
		end if
	end try
	return false
end msgAccountAccountStatus

on msgAccountStatus(tmout)
	-- 60 seconds
	set procStart to current date
	set pass to false
	repeat until pass
		if (current date) - procStart is greater than tmout then
			return false
		end if
		try
			with timeout of msgActivateTimeout seconds
				activate application "Messages"
			end timeout
			set windowStatus to msgWindowStatus(tmout - ((current date) - procStart))
			if windowStatus is equal to "Main" then
				set mainWindowStatus to msgMainWindowStatus(tmout - ((current date) - procStart))
				if mainWindowStatus is equal to "Account" then
					return false
				else
					with timeout of msgOperateTimeout seconds
						tell application "System Events" to click menu item 3 of menu 1 of menu bar item 2 of menu bar 1 of process "Messages"
					end timeout
				end if
			end if
			set pass to true
		on error errMsg number errorNumber
			if errorNumber is equal to -1719 then
			else
				set pass to true
			end if
		end try
	end repeat
	set windowStatus to msgWindowStatus(tmout - ((current date) - procStart))
	if windowStatus is equal to "Account" then
		return msgAccountAccountStatus(tmout - ((current date) - procStart))
	end if
	return false
end msgAccountStatus

on msgReceiverCount(tmout)
	-- 2 seconds
	set procStart to current date
	local errMsg, errorNumber
	try
		with timeout of msgActivateTimeout seconds
			activate application "Messages"
		end timeout
		with timeout of msgReadTimeout seconds
			tell application "System Events"
				if (count text fields of scroll area 2 of splitter group 1 of window 1 of process "Messages") is greater than 0 then
					return (count menu buttons of text field 1 of scroll area 2 of splitter group 1 of window 1 of process "Messages")
				else if (count static texts of scroll area 2 of splitter group 1 of window 1 of process "Messages") is greater than 0 then
					return (count menu buttons of static text 1 of scroll area 2 of splitter group 1 of window 1 of process "Messages")
				end if
			end tell
		end timeout
		return 0
	on error errMsg number errorNumber
		setErrors(errMsg, errorNumber, "msgReceiverCount")
		return missing value
	end try
end msgReceiverCount

on msgChatCount(tmout)
	-- 2 seconds
	set procStart to current date
	local errMsg, errorNumber
	try
		with timeout of msgActivateTimeout seconds
			activate application "Messages"
		end timeout
		with timeout of msgReadTimeout seconds
			tell application "System Events" to set returnVal to (count rows of table 1 of scroll area 1 of splitter group 1 of window 1 of process "Messages")
		end timeout
		if returnVal is equal to 1 then
			with timeout of msgReadTimeout seconds
				tell application "System Events"
					if (count rows of UI element 1 of row 1 of table 1 of scroll area 1 of splitter group 1 of window 1 of process "Messages") is equal to 0 then
						return 0
					end if
				end tell
			end timeout
		end if
		return returnVal
	on error errMsg number errorNumber
		setErrors(errMsg, errorNumber, "msgChatCount")
		return missing value
	end try
end msgChatCount

on msgAssertMainWindow(tmout)
	-- 42 seconds
	set procStart to current date
	try
		with timeout of msgActivateTimeout seconds
			activate application "Messages"
		end timeout
		set windowStatus to msgWindowStatus(tmout - ((current date) - procStart))
		if windowStatus is equal to "Account" then
			with timeout of msgOperateTimeout seconds
				tell application "System Events" to click button 1 of window 1 of process "Messages"
			end timeout
			set windowStatus to msgWindowStatus(tmout - ((current date) - procStart))
		end if
		if windowStatus is equal to "Main" then
			set mainWindowStatus to msgMainWindowStatus(tmout - ((current date) - procStart))
			if mainWindowStatus is in {"Delete", "Send"} then
				with timeout of msgOperateTimeout seconds
					tell application "System Events" to click button 1 of sheet 1 of window 1 of process "Messages"
				end timeout
				set mainWindowStatus to msgMainWindowStatus(tmout - ((current date) - procStart))
			end if
			if mainWindowStatus is equal to "Main" then
				return true
			end if
		end if
		return false
	on error
		return false
	end try
end msgAssertMainWindow

on msgClearReceiver(tmout)
	-- 50 seconds
	set procStart to current date
	local errMsg, errorNumber
	try
		with timeout of msgActivateTimeout seconds
			activate application "Messages"
		end timeout
		if msgAssertMainWindow(tmout) is equal to true then
			with timeout of msgOperateTimeout seconds
				tell application "System Events" to set value of text field 1 of scroll area 2 of splitter group 1 of window 1 of process "Messages" to ""
			end timeout
			delay msgWaitInWindow
			if msgReceiverCount(tmout - ((current date) - procStart)) is equal to 0 then
				return true
			end if
		end if
	on error errMsg number errorNumber
		setErrors(errMsg, errorNumber, "msgClearReceiver")
		error errMsg number errorNumber
	end try
	return false
end msgClearReceiver

on msgClearChat(tmout)
	-- 77 seconds
	set procStart to current date
	local errMsg, errorNumber
	try
		with timeout of msgActivateTimeout seconds
			activate application "Messages"
		end timeout
		if msgAssertMainWindow(tmout) is equal to true then
			with timeout of msgOperateTimeout seconds
				tell application "Messages" to decline chats
			end timeout
			set chatCount to msgChatCount(tmout - ((current date) - procStart))
			if chatCount is equal to missing value then
				return false
			else if chatCount is greater than 0 then
				repeat until msgChatCount(tmout - ((current date) - procStart)) is equal to 0
					if (current date) - procStart is greater than tmout then
						return false
					end if
					with timeout of msgOperateTimeout seconds
						tell application "Messages" to decline chats
						tell application "System Events" to click menu item 11 of menu 1 of menu bar item 3 of menu bar 1 of process "Messages"
					end timeout
					if msgMainWindowStatus(tmout - ((current date) - procStart)) is equal to "Delete" then
						with timeout of msgOperateTimeout seconds
							tell application "System Events" to click button 1 of sheet 1 of window 1 of process "Messages"
						end timeout
					end if
					delay msgWaitInWindow
				end repeat
			end if
		end if
		return true
	on error errMsg number errorNumber
		setErrors(errMsg, errorNumber, "msgClearChat")
		error errMsg number errorNumber
	end try
	return false
end msgClearChat

on msgQuit(tmout)
	-- 107 seconds
	set procStart to current date
	try
		with timeout of msgReadTimeout seconds
			tell application "System Events" to set isRunMessages to (exists process "Messages")
		end timeout
		if not isRunMessages then
			msgClearChat(tmout)
		end if
	end try
	try
		with timeout of msgLaunchTimeout seconds
			tell application "Messages" to quit
		end timeout
	end try
	try
		do shell script "/usr/bin/killall Messages imagent UserNotificationCenter"
		do shell script "/bin/rm -rf /Users/adways/Library/Messages/Archive/"
	end try
	return true
end msgQuit

on msgNewChat(tmout)
	-- 57 seconds
	set procStart to current date
	local errMsg, errorNumber
	try
		with timeout of msgActivateTimeout seconds
			activate application "Messages"
		end timeout
		if msgAssertMainWindow(tmout) is equal to true then
			set chatCount to msgChatCount(tmout - ((current date) - procStart))
			set receiverCount to msgReceiverCount(tmout - ((current date) - procStart))
			with timeout of msgOperateTimeout seconds
				tell application "System Events" to click button 1 of group 1 of splitter group 1 of window 1 of process "Messages"
			end timeout
			delay msgWaitSwitchWindow
			if receiverCount is not equal to missing value and chatCount is not equal to missing value then
				if ((receiverCount is greater than 0) or (chatCount is equal to 0 and receiverCount is equal to 0)) then
					if (msgChatCount(tmout - ((current date) - procStart)) is equal to chatCount + 1) and (msgReceiverCount(tmout - ((current date) - procStart)) is equal to 0) then
						return true
					end if
				else
					return true
				end if
			else
				return false
			end if
		end if
	on error errMsg number errorNumber
		setErrors(errMsg, errorNumber, "msgNewChat")
		error errMsg number errorNumber
	end try
	return false
end msgNewChat

on msgAddReceiver(teleList, tmout)
	-- 85 seconds
	set procStart to current date
	local errMsg, errorNumber
	try
		with timeout of msgActivateTimeout seconds
			activate application "Messages"
		end timeout
		if msgAssertMainWindow(tmout) is equal to true then
			set receiverCount to msgReceiverCount(tmout - ((current date) - procStart))
			set receivers to joinReceiver(teleList)
			with timeout of msgOperateTimeout seconds
				tell application "System Events"
					set focused of text field 1 of scroll area 2 of splitter group 1 of window 1 of process "Messages" to true
					set value of text field 1 of scroll area 2 of splitter group 1 of window 1 of process "Messages" to receivers
					keystroke return
					keystroke return
				end tell
			end timeout
			delay msgWaitInWindow
			msgDealWithNotification(tmout - ((current date) - procStart))
			with timeout of msgActivateTimeout seconds
				activate application "Messages"
			end timeout
			if msgReceiverCount(tmout - ((current date) - procStart)) is equal to receiverCount + (count teleList) then
				return true
			end if
		end if
	on error errMsg number errorNumber
		setErrors(errMsg, errorNumber, "msgAddReceiver")
		error errMsg number errorNumber
	end try
	return false
end msgAddReceiver

on msgCaptureDetectReceiver(teleNum, tmout)
	-- 3 seconds
	set procStart to current date
	with timeout of msgActivateTimeout seconds
		activate application "Messages"
	end timeout
	with timeout of msgReadTimeout seconds
		tell application "System Events"
			set receiver to text field 1 of scroll area 2 of splitter group 1 of window 1 of process "Messages"
			set s to size of receiver
			set l to position of receiver
		end tell
	end timeout
	do shell script "/usr/sbin/screencapture -R" & (item 1 of l as integer) & "," & (item 2 of l as integer) & "," & (item 1 of s as integer) & "," & (item 2 of s as integer) & " /Users/adways/Documents/r.png"
	set results to paragraphs of (do shell script "/Users/adways/Documents/imDetector /Users/adways/Documents/r.png " & teleNum & " " & getSettings("client_checker_color_diffrence"))
	do shell script "/bin/rm /Users/adways/Documents/r.png"
	return results
end msgCaptureDetectReceiver

on msgLogout(tmout)
	-- 196 seconds
	set procStart to current date
	try
		with timeout of msgActivateTimeout seconds
			activate application "Messages"
		end timeout
		set accountStatus to msgAccountStatus(tmout)
		if accountStatus then
			with timeout of msgOperateTimeout seconds
				tell application "System Events" to click menu item 3 of menu 1 of menu bar item 2 of menu bar 1 of process "Messages"
			end timeout
			delay msgWaitSwitchWindow
			with timeout of msgOperateTimeout seconds
				tell application "System Events"
					click button 2 of tool bar 1 of window 1 of process "Messages"
					click button 3 of group 1 of group 2 of group 1 of group 1 of window 1 of process "Messages"
					click button 1 of sheet 1 of window 1 of process "Messages"
				end tell
			end timeout
			delay msgWaitSwitchWindow
			with timeout of msgOperateTimeout seconds
				tell application "System Events" to click button 1 of window 1 of process "Messages"
			end timeout
		end if
		msgQuit(tmout - ((current date) - procStart))
		cleanDB()
		do shell script "/bin/rm -rf /Users/adways/Library/Messages/chat.db*"
	end try
end msgLogout

on msgCheckStatusOnErrorClear(tmout)
	-- 246 seconds
	set procStart to current date
	local errMsg, errorNumber
	msgStartProc(tmout)
	set pass to false
	repeat until pass
		if (current date) - procStart is greater than tmout then
			return false
		end if
		try
			with timeout of msgActivateTimeout seconds
				activate application "Messages"
			end timeout
			set windowStatus to msgWindowStatus(tmout - ((current date) - procStart))
			if windowStatus is equal to "NotRun" then
				with timeout of msgReadTimeout seconds
					tell application "System Events" to set isRunMessages to (exists process "Messages")
				end timeout
				if isRunMessages then
					msgQuit(tmout - ((current date) - procStart))
					delay msgWaitSwitchProc
				end if
				msgStartProc(tmout - ((current date) - procStart))
				set pass to false
			else if windowStatus is equal to "Error" then
				with timeout of msgOperateTimeout seconds
					tell application "System Events" to click button 1 of window 1 of process "Messages"
				end timeout
				delay msgWaitSwitchProc
				msgStartProc(tmout - ((current date) - procStart))
				set pass to false
			else if windowStatus is equal to "Send" then
				with timeout of msgOperateTimeout seconds
					tell application "System Events" to click button 1 of window 1 of process "Messages"
				end timeout
				set pass to false
			else if windowStatus is equal to "Main" then
				set mainWindowStatus to msgMainWindowStatus(tmout - ((current date) - procStart))
				if mainWindowStatus is in {"Account", "AccountFail"} then
					return false
				else if mainWindowStatus is equal to "Main" then
					if msgAccountStatus(tmout - ((current date) - procStart)) then
						with timeout of msgOperateTimeout seconds
							tell application "System Events" to click button 1 of window 1 of process "Messages"
						end timeout
						set pass to true
					else
						return false
					end if
				else if mainWindowStatus is in {"Delete", "Send"} then
					with timeout of msgOperateTimeout seconds
						tell application "System Events" to click button 1 of sheet 1 of window 1 of process "Messages"
					end timeout
					if msgAccountStatus(tmout - ((current date) - procStart)) then
						with timeout of msgOperateTimeout seconds
							tell application "System Events" to click button 1 of window 1 of process "Messages"
						end timeout
						set pass to true
					else
						return false
					end if
				else if mainWindowStatus is equal to "Unknown" then
					return false
				end if
			else if windowStatus is equal to "Account" then
				if msgAccountStatus(tmout - ((current date) - procStart)) then
					with timeout of msgOperateTimeout seconds
						tell application "System Events" to click button 1 of window 1 of process "Messages"
					end timeout
					set pass to true
				else
					return false
				end if
			else if windowStatus is equal to "Unknown" then
				return false
			end if
		on error errMsg number errorNumber
			if errorNumber is in {-1719, -1728} then
			else
				set pass to true
				setErrors(errMsg, errorNumber, "msgCheckStatusOnErrorClear")
				return false
			end if
		end try
	end repeat
	return true
end msgCheckStatusOnErrorClear

on msgLogin(tmout)
	-- 210 seconds
	set procStart to current date
	try
		msgStartProc(tmout)
		set windowStatus to msgWindowStatus(tmout - ((current date) - procStart))
		if windowStatus is equal to "Main" then
			set mainWindowStatus to msgMainWindowStatus(tmout - ((current date) - procStart))
			if mainWindowStatus is equal to "Account" then
				set account to getClientInfo("account") as string
				set psword to getClientInfo("password") as string
				with timeout of msgActivateTimeout seconds
					activate application "Messages"
				end timeout
				repeat
					if (current date) - procStart is greater than tmout then
						return false
					end if
					-- Input Account, Password
					with timeout of msgOperateTimeout seconds
						tell application "System Events"
							set value of text field 1 of group 1 of group 1 of group 1 of sheet 1 of window 1 of process "Messages" to account
							keystroke tab
							set value of text field 2 of group 1 of group 1 of group 1 of sheet 1 of window 1 of process "Messages" to psword
							click button 2 of sheet 1 of window 1 of process "Messages"
						end tell
					end timeout
					delay msgWaitSwitchWindow
					repeat
						if (current date) - procStart is greater than tmout then
							return false
						end if
						-- Login
						msgDealWithNotification(tmout - ((current date) - procStart))
						with timeout of msgActivateTimeout seconds
							activate application "Messages"
						end timeout
						with timeout of msgReadTimeout seconds
							tell application "System Events" to set buttonName to name of button 1 of sheet 1 of window 1 of process "Messages"
						end timeout
						if buttonName is equal to "返回" then
							exit repeat
						else
							try
								with timeout of msgReadTimeout seconds
									tell application "System Events"
										set busyIdc to value of busy indicator 1 of group 1 of group 1 of group 1 of sheet 1 of window 1 of process "Messages"
										set btnEab to enabled of button 2 of sheet 1 of window 1 of process "Messages"
									end tell
								end timeout
								if btnEab is equal to false and (busyIdc is equal to missing value or busyIdc is equal to false) then
									return false
								else if btnEab is equal to true and (busyIdc is equal to missing value or busyIdc is equal to false) then
									with timeout of msgOperateTimeout seconds
										tell application "System Events" to click button 2 of sheet 1 of window 1 of process "Messages"
									end timeout
								end if
							end try
						end if
					end repeat
					with timeout of msgReadTimeout seconds
						tell application "System Events" to set accountChecked to value of checkbox 1 of UI element 1 of row 1 of table 1 of scroll area 1 of group 1 of group 1 of group 1 of sheet 1 of window 1 of process "Messages"
					end timeout
					if accountChecked is equal to 1 then
						with timeout of msgOperateTimeout seconds
							tell application "System Events" to click button 2 of sheet 1 of window 1 of process "Messages"
							exit repeat
						end timeout
					else
						with timeout of msgOperateTimeout seconds
							tell application "System Events" to click button 1 of sheet 1 of window 1 of process "Messages"
						end timeout
						delay msgWaitSwitchWindow
					end if
				end repeat
			end if
			delay msgWaitSwitchWindow
			set acStatus to msgAccountStatus(tmout - ((current date) - procStart))
			repeat
				if (current date) - procStart is greater than tmout then
					return false
				end if
				with timeout of msgReadTimeout seconds
					tell application "System Events" to set cntSheets to count sheets of window 1 of process "Messages"
				end timeout
				if cntSheets is greater than 0 then
					with timeout of msgOperateTimeout seconds
						tell application "System Events" to click button 1 of sheet 1 of window 1 of process "Messages"
					end timeout
					return false
				end if
				msgDealWithNotification(tmout - ((current date) - procStart))
				with timeout of msgActivateTimeout seconds
					activate application "Messages"
				end timeout
				with timeout of msgReadTimeout seconds
					tell application "System Events"
						set statusAccount to value of checkbox 2 of group 1 of group 2 of group 1 of group 1 of window 1 of process "Messages"
						set statusAccountEnable to enabled of checkbox 2 of group 1 of group 2 of group 1 of group 1 of window 1 of process "Messages"
					end tell
				end timeout
				if statusAccount is equal to 1 and statusAccountEnable is equal to true then
					with timeout of msgOperateTimeout seconds
						tell application "System Events" to click button 1 of window 1 of process "Messages"
					end timeout
					return true
				else
					delay msgWaitInWindow
				end if
			end repeat
		end if
		return false
	on error
		return false
	end try
end msgLogin

on msgCheckAccounts(teleList, tmout)
	-- 179 seconds
	set procStart to current date
	local errMsg, errorNumber
	set results to {}
	try
		with timeout of msgActivateTimeout seconds
			activate application "Messages"
		end timeout
		if msgNewChat(tmout) then
			set groupedTeleList to groupList(teleList, 10)
			repeat with tList in groupedTeleList
				if msgAddReceiver(tList, tmout - ((current date) - procStart)) then
					delay getSettings("client_checker_wait") as real
					set captureResults to msgCaptureDetectReceiver(count tList, tmout - ((current date) - procStart))
					set sumResults to 0
					repeat with captureR in captureResults
						if captureR is equal to "ERROR" then
							error "imDetector failed"
						end if
						if captureR as integer is equal to 1 then
							set results to results & true
						else
							set results to results & false
						end if
						set sumResults to sumResults + captureR as integer
					end repeat
					if (getSettings("client_checker_credibility_check") as integer is equal to 1) and sumResults is greater than 4 then
						addUncreditTasks(tList)
						set creditCount to 99999
						exit repeat
					else if sumResults is equal to 0 then
						addUncreditTasks(tList)
						set creditCount to creditCount + (count tList)
					else
						commitUncreditTasks()
						set creditCount to 0
					end if
					msgClearReceiver(tmout - ((current date) - procStart))
				else
					error "msgAddReceiver() failed"
				end if
			end repeat
			msgClearChat(tmout - ((current date) - procStart))
		else
			error "msgNewChat() failed"
		end if
	on error errMsg number errorNumber
		setErrors(errMsg, errorNumber, "msgCheckAccounts")
		setClientStatus(3)
	end try
	return results
end msgCheckAccounts

on msgSendMsg(teleMsgList, tmout)
	-- 31 seconds
	set procStart to current date
	local errMsg, errorNumber
	if not checkIsAllowSend() then
		return {}
	end if
	set results to {}
	try
		with timeout of msgActivateTimeout seconds
			activate application "Messages"
		end timeout
		repeat with tLine in teleMsgList
			try
				set tele to item 1 of tLine
				set msg to item 2 of tLine
				with timeout of msgOperateTimeout seconds
					tell application "Messages"
						set ServiceiMessage to first item of (every service whose service type is iMessage)
						send msg to buddy tele of ServiceiMessage
					end tell
				end timeout
				delay getSettings("client_sender_wait") as real
				set mainStatus to msgWindowStatus(tmout - ((current date) - procStart))
				if mainStatus is equal to "Main" then
					set mainWindowStatus to msgMainWindowStatus(tmout - ((current date) - procStart))
					if mainWindowStatus is equal to "Send" then
						with timeout of msgOperateTimeout seconds
							tell application "System Events" to click button 1 of sheet 1 of window 1 of process "Messages"
						end timeout
						set results to results & false
					else if mainWindowStatus is equal to "Main" then
						set results to results & true
					else
						set results to results & false
					end if
				else if mainStatus is equal to "Send" then
					with timeout of msgOperateTimeout seconds
						tell application "System Events" to click button 1 of window 1 of process "Messages"
					end timeout
					set results to results & false
				else
					set results to results & false
				end if
			on error
				set results to results & false
			end try
		end repeat
	on error errMsg number errorNumber
		setErrors(errMsg, errorNumber, "msgSendMsg")
		setClientStatus(3)
	end try
	return results
end msgSendMsg

on msgClearChatByIds(chatIds, tmout)
	-- 5 seconds
	set procStart to current date
	with timeout of msgActivateTimeout seconds
		activate application "Messages"
	end timeout
	repeat with chatId in chatIds
		with timeout of msgOperateTimeout seconds
			try
				tell application "Messages" to decline chat id chatId
			end try
		end timeout
	end repeat
end msgClearChatByIds


--=====================================
-- Logic Functions
--=====================================


on checkAccounts()
	set checkNum to getSettings("client_checker_result_count") as integer
	if (count checkTaskList) is less than checkNum then
		getCheckTasks()
	end if
	if (count checkTaskList) is greater than 0 then
		set succTeles to {}
		set failTeles to {}
		set teleList to mapList(checkTaskList, 3)
		set checkResults to msgCheckAccounts(teleList, 180)
		repeat with i from 1 to count checkResults
			set tele to first item of checkTaskList
			if item i of checkResults is equal to true then
				set succTeles to succTeles & {tele}
			else
				set failTeles to failTeles & {tele}
			end if
			set checkTaskList to rest of checkTaskList
		end repeat
		setCheckTaskResults(succTeles, failTeles)
	else
		setClientStatus(4)
	end if
end checkAccounts

on checkCreditAccounts()
	set creditResult to true
	set teleStatusList to getCreditTasks()
	set teleList to mapList(teleStatusList, 1)
	set checkResults to msgCheckAccounts(teleList, 180)
	set sumResults to 0
	repeat with checkResult in checkResults
		if checkResult then
			set sumResults to sumResults + 1
		end if
	end repeat
	
	if sumResults is less than 1 or sumResults is greater than 4 then
		setClientStatus(5)
		if getClientInfo("retry") is equal to 0 then
			msgLogout(240)
		else
			msgQuit(120)
		end if
		rollbackUncreditTasks()
		set creditCount to 0 as integer
		return false
	else
		commitUncreditTasks()
		set creditCount to 0 as integer
		return true
	end if
end checkCreditAccounts

on sendAccounts()
	if not checkIsAllowSend() then
		return
	end if
	set sendNum to getSettings("client_sender_result_count") as integer
	if (count sendTaskList) is less than sendNum then
		getSendTasks()
	end if
	if (count sendTaskList) is greater than 0 then
		set succTeles to {}
		set failTeles to {}
		set teleMsgList to mapList(sendTaskList, {3, 4})
		set sendResults to msgSendMsg(teleMsgList, (count teleMsgList) * 30)
		repeat with i from 1 to count sendResults
			set tele to first item of sendTaskList
			if item i of sendResults is equal to true then
				set succTeles to succTeles & {tele}
			else
				set failTeles to failTeles & {tele}
			end if
			set sendTaskList to rest of sendTaskList
		end repeat
		set waitingSendList to waitingSendList & mapList(succTeles, {1, 2, 3})
		set allFailCount to allFailCount + (count failTeles)
		setSendTaskResults({}, failTeles)
		
		waitSend(2)
	else
		setClientStatus(4)
	end if
end sendAccounts

on waitSend(tmout)
	set procStart to current date
	repeat while (count waitingSendList) is greater than 0
		if (current date) - procStart is greater than tmout then
			return false
		end if
		set succList to getAccountsDelivered()
		set waitingList to getAccountsWaiting()
		set timeoutList to getAccountsWaitingTimeout(getSettings("client_sender_sent_timeout") as integer)
		set failList to getAccountsFailed()
		if ((count waitingList) is less than (count waitingSendList)) or ((count succList) is greater than 0) then
			set declineList to mapList(succList, 1) & mapList(failList, 1) & mapList(timeoutList, 1)
			msgClearChatByIds(declineList, (count declineList))
			set {succTeles, waitingSendList} to pickList(waitingSendList, succList, 3, 2)
			set {waitingSendList, failTeles} to pickList(waitingSendList, waitingList, 3, 2)
			set {timeoutTeles, waitingSendList} to pickList(waitingSendList, timeoutList, 3, 2)
			
			setSendTimeout(timeoutTeles)
			if (count succTeles) is equal to 0 then
				set allFailCount to allFailCount + (count failTeles)
			else
				set allFailCount to 0
			end if
			if (count succTeles) + (count failTeles) is greater than 0 then
				setSendTaskResults(succTeles, failTeles)
			end if
		end if
		delay (tmout / 3)
	end repeat
	return true
end waitSend
