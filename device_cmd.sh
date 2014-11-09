#!/bin/sh

# Usage: ./device_cmd.sh setting <id> <version>
#        ./device_cmd.sh network <id> <mac> <ip>
#        ./device_cmd.sh account <id>
#        ./device_cmd.sh login <id> <status>
#        ./device_cmd.sh sender <id>
#        ./device_cmd.sh logout <id>

cmd=$1
mysql="/usr/local/mysql/bin/mysql --defaults-extra-file=/home/mobile/my.cnf -s -N -e "

help() {
	/bin/echo "Usage: ./device_cmd.sh setting <id> <version>"
	/bin/echo "       ./device_cmd.sh network <id> <mac> <ip>"
	/bin/echo "       ./device_cmd.sh account <id>"
	/bin/echo "       ./device_cmd.sh login <id> <status>"
	/bin/echo "       ./device_cmd.sh sender <id>"	
	/bin/echo "       ./device_cmd.sh logout <id>"	
}

load_setting() {
	id=$1
    version=$2
	setting=`$mysql "SELECT setting_value FROM settings WHERE setting_key LIKE 'device_%' ORDER BY FIELD(setting_key, 'device_lastest_version', 'device_network_timeout', 'device_login_timeout', 'device_sync_timeout')"`
	$mysql "UPDATE device SET last_action = 'activate', version = '$version' WHERE id = $id"
	/bin/echo $setting
}

network_succ() {
	id=$1
	mac=$2
	ip=$3
	$mysql "INSERT INTO device_network(device_id, mac, ip) VALUES ($id, '$mac', '$ip')"
	$mysql "UPDATE device SET last_action = 'network' WHERE id = $id"
}

get_account() {
	id=$1
	account_id=`$mysql "SELECT account_id FROM device_account WHERE device_id = $id AND login_status = 0 ORDER BY id DESC LIMIT 1"`
	if [[ $account_id == "" ]]; then
		send_type=`$mysql "SELECT setting_value FROM settings WHERE setting_key='send_type'"`
		$mysql "UPDATE account a join (select a.id from account a join account_domain d on a.domain_id=d.id and d.send_type=$send_type WHERE a.status = 0 AND a.device_id = 0 AND a.priority > 0 AND a.next_allow_time <= CURRENT_TIMESTAMP ORDER BY a.priority DESC, RAND() LIMIT 1) t on a.id=t.id set a.device_id = $id"
		account_id=`$mysql "SELECT id FROM account WHERE status = 0 AND device_id = $id LIMIT 1"`
		if [[ $account_id != "" ]]; then
			$mysql "INSERT INTO device_account(device_id, account_id) VALUES($id, $account_id)"
			$mysql "UPDATE account SET status = 1, device_id = 0, priority = priority - 1 WHERE id = $account_id"
		fi
	fi
	if [[ $account_id != "" ]]; then
		account=`$mysql "SELECT account, passwd FROM account WHERE id = $account_id"`
		$mysql "UPDATE device SET last_action = 'login' WHERE id = $id"
		/bin/echo $account
	fi
}

login_succ() {
	id=$1
	device_account_id=`$mysql "SELECT id FROM device_account WHERE device_id = $id AND login_status = 0 ORDER BY id DESC LIMIT 1"`
	if [[ $device_account_id != "" ]]; then
		$mysql "UPDATE device_account SET login_status = 1, login_time = CURRENT_TIMESTAMP WHERE id = $device_account_id"
		$mysql "UPDATE device SET last_action = 'wait_vm' WHERE id = $id"
	fi
}

login_fail() {
	id=$1
	device_account_id=`$mysql "SELECT id FROM device_account WHERE device_id = $id AND login_status = 0 ORDER BY id DESC LIMIT 1"`
	if [[ $device_account_id != "" ]]; then
		$mysql "UPDATE device_account d, account a SET d.login_status = 2, a.status = 0 WHERE d.id = $device_account_id AND d.account_id = a.id"
	fi
}

check_sender() {
	id=$1
	device_account_id=`$mysql "SELECT id FROM device_account WHERE device_id = $id AND login_status = 1 AND sync_status IN (0,3) LIMIT 1"`
	if [[ $device_account_id != "" ]]; then
		/bin/echo "0"
	else
		status=`$mysql "SELECT sync_status FROM device_account WHERE device_id = $id AND login_status = 1 ORDER BY id DESC LIMIT 1"`
		$mysql "UPDATE device SET last_action = 'vm_reply' WHERE id = $id"
		/bin/echo "$status"
	fi
}

logout_succ() {
	id=$1
	device_account_id=`$mysql "SELECT id FROM device_account WHERE device_id = $id AND login_status = 1 ORDER BY id DESC LIMIT 1"`
	if [[ $device_account_id != "" ]]; then
		$mysql "UPDATE device_account SET login_status = 3 WHERE id = $device_account_id"
	fi
	$mysql "UPDATE device SET last_action = 'logout' WHERE id = $id"
}

case $cmd in
	setting)
		if [[ $# -eq 3 ]]; then
			load_setting $2 $3
        elif [[ $# -eq 2 ]]; then
            load_setting $2 10003
		else
			help
		fi
		;;
	network)
		if [[ $# -eq 4 ]]; then
			network_succ $2 $3 $4
		else
			help
		fi
		;;
	account)
		if [[ $# -eq 2 ]]; then
			get_account $2
		else
			help
		fi
		;;
	login)
		if [[ $# -eq 3 ]]; then
			status=$3
			if [[ $status == "1" ]]; then
				login_succ $2
			else
				login_fail $2
			fi
		else
			help
		fi
		;;
	sender)
		if [[ $# -eq 2 ]]; then
			check_sender $2
		else
			help
		fi
		;;
	logout)
		if [[ $# -eq 2 ]]; then
			logout_succ $2
		else
			help
		fi
		;;
	*)
		help
		;;
esac

