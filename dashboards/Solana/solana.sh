#!/bin/bash
# Config
daemon="$HOME/.local/share/solana/install/active_release/bin/solana"
identity_address=""
vote_address=""
sqlite_db="$HOME/.monitoring/telegraf/solana.db"

# Functions
main() {
	mkdir -p "$HOME/.monitoring/telegraf/"
	local host=`grep "hostname" /etc/telegraf/telegraf.conf | grep -oPm1 "(?<=\")([^%]+)(?=\")"`
	local influxdb_url=`grep "urls" /etc/telegraf/telegraf.conf | grep -oPm1 "(?<=\")([^%]+)(?=\")"`
	local influxdb_database=`grep "database" /etc/telegraf/telegraf.conf | grep -oPm1 "(?<=\")([^%]+)(?=\")"`
	local influxdb_user=`grep "username" /etc/telegraf/telegraf.conf | grep -oPm1 "(?<=\")([^%]+)(?=\")"`
	local influxdb_password=`grep "password" /etc/telegraf/telegraf.conf | grep -oPm1 "(?<=\")([^%]+)(?=\")"`
	
	local voting=`ps aux | grep solana-validator | grep "\-\-no\-voting"`
	if [ -n "$voting" ]; then
		echo "The validator isn't voting!"
		exit 1
	fi
	
	local running=`ps aux | grep solana-validator | grep "\-\-identity"`
	if [ -n "$running" ]; then
		local rpc_port=`ps aux | grep solana-validator | grep -oPm1 "\-\-rpc\-port\s+\K[0-9]+"`
		if [ ! -n "$rpc_port" ]; then
			local rpc_port=8899
		fi
		local rpc_url="-u http://127.0.0.1:$rpc_port"
		local cluster_slot=`$daemon slot`
		local validator_slot=`$daemon slot $rpc_url`
		local diff=$((cluster_slot-validator_slot))
		if [ "$diff" -ge 10 ]; then
			local syncing="true"
			local rpc_url=""			
		fi
	else
		local rpc_url=""
	fi
	local validators=`$daemon validators $rpc_url --output json-compact`
	if [ ! -n "$identity_address" ]; then
		local identity_address=`$daemon address $rpc_url 2>/dev/null`
	fi
	if [ ! -n "$identity_address" ]; then
		echo "Failed to parse the identity address, specify it in the script config!"
		exit 1
	fi
	if [ ! -n "$vote_address" ]; then
		local vote_address=`jq -r 'first (.validators[] | select(.identityPubkey == "'$identity_address'")) | .voteAccountPubkey' <<< "$validators" 2>/dev/null`
	fi
	if [ ! -n "$vote_address" ]; then
		echo "Failed to parse the vote address, specify it in the script config!"
		exit 1
	fi
	
	local epoch_info=`$daemon epoch-info`
	local current_epoch=`grep "Epoch:" <<< "$epoch_info" | awk '{print $(NF)}'`
	local epoch_progress=`grep "Epoch Completed Percent:" <<< "$epoch_info" | awk '{print $(NF)}' | tr -d '%'`
	
	local epoch_remaining_time=`grep "Epoch Completed Time:" <<< "$epoch_info" | grep -oPm1 "(?<=\()([^%]+)(?= remaining)" | tr ' ' '\n'`
	local days_remaining=`grep -oE "[0-9]+day" <<< "$epoch_remaining_time" | grep -oE '[0-9]+'`
	local hours_remaining=`grep -oE "[0-9]+h" <<< "$epoch_remaining_time" | grep -oE '[0-9]+'`
	local minutes_remaining=`grep -oE "[0-9]+m" <<< "$epoch_remaining_time" | grep -oE '[0-9]+'`
	local seconds_remaining=`grep -oE "[0-9]+s" <<< "$epoch_remaining_time" | grep -oE '[0-9]+'`
	if [ ! -n "$days_remaining" ]; then local days_remaining=0; fi
	if [ ! -n "$hours_remaining" ]; then local hours_remaining=0; fi
	if [ ! -n "$minutes_remaining" ]; then local minutes_remaining=0; fi
	if [ ! -n "$seconds_remaining" ]; then local seconds_remaining=0; fi
	local epoch_end_time=`bc <<< "($(date +%s)+$days_remaining*86400+$hours_remaining*3600+$minutes_remaining*60+$seconds_remaining)*1000" 2>/dev/null`
	
	local solana_log=`tail -n10000 $HOME/solana/solana.log 2>/dev/null`
	if [ -n "$solana_log" ]; then
		local slots_remaining=`echo "$solana_log" | awk -v pattern="$(solana address).+within slot" '$0 ~ pattern {printf "%d\n", $18-$12}' | tail -1`
		local leader_slot_time=`bc <<< "scale=0; $slots_remaining*0.5/1" 2>/dev/null`
		if [ ! -n "$leader_slot_time" ]; then
			local leader_slot_time=0
		fi
	else
		local leader_slot_time=0
	fi
	
	local validator_info=`jq -r '.validators[] | select(.voteAccountPubkey == "'$vote_address'")' <<< "$validators"`
	if [ -n "$running" ]; then
		if [ -n "$syncing" ]; then
			local status="Syncing"
		elif [ `jq -r ".delinquent" <<< "$validator_info"` = "false" ]; then
			local status="Running"
		else
			local status="Delinquent"
		fi
	else
		local status="Not running"
	fi
	local version=`jq -r ".version" <<< "$validator_info"`		
	local validator_commission=`jq -r ".commission" <<< "$validator_info"`
	local identity_balance=`$daemon balance $identity_address $rpc_url | grep -oE '[0-9]+.[0-9]+'`
	local vote_balance=`$daemon balance $vote_address $rpc_url | grep -oE '[0-9]+.[0-9]+'`
	if ! grep -q "$vote_address" <<< "$validators" ; then
		echo "There is no validator in the set!"
		exit 1
	fi
	
	local solana_price=`wget -qO- https://api.binance.com/api/v3/ticker/price?symbol=SOLUSDT | jq -r ".price"`
	local block_production=`$daemon block-production $rpc_url --output json-compact`
	local validator_block_production=`jq -r '.leaders[] | select(.identityPubkey == "'$identity_address'")' <<< "$block_production"`
	local total_slots=`$daemon leader-schedule | grep $identity_address | wc -l`
	if [ -n "$validator_block_production" ]; then
		local passed_slots=`jq -r ".leaderSlots" <<< "$validator_block_production"`
		local skipped_slots=`jq -r ".skippedSlots" <<< "$validator_block_production"`
		local validator_skip_rate=`bc <<< "scale=3; 100*$skipped_slots/$passed_slots" 2>/dev/null`
	else
		local passed_slots=0
		local skipped_slots=0
		local validator_skip_rate=0.000
	fi
	local cluster_skip_rate=`bc <<< "scale=3; 100*$(jq ".total_slots_skipped" <<< "$block_production")/$(jq ".total_slots" <<< "$block_production")" 2>/dev/null`
	
	local credits=`$daemon vote-account $vote_address | grep -oPm1 "(?<=credits/slots: )([^%]+)(?=/)"`
	local stake=`bc <<< "scale=3; $(jq -r ".activatedStake" <<< "$validator_info")/1000000000" 2>/dev/null`
	
	sqlite3 "$sqlite_db" "CREATE TABLE IF NOT EXISTS leader_slots (epoch INTEGER, slot INTEGER UNIQUE, reward REAL)"
	for slot in `$daemon block-production $rpc_url -v | grep $identity_address | grep -v SKIPPED | sed 1d | awk '{print $1}'`; do
		sqlite3 "$sqlite_db" "INSERT INTO leader_slots (epoch, slot) VALUES ($current_epoch, $slot)" 2>/dev/null
	done
	for check_slot in `sqlite3 "$sqlite_db" "SELECT slot FROM leader_slots WHERE reward IS NULL"`; do
		local slot_reward=`$daemon block $check_slot | grep $identity_address | grep "%" | awk '{print $3}' | grep -oE '[0-9]+.[0-9]+' | paste -sd+ | bc`
		sqlite3 "$sqlite_db" "UPDATE leader_slots SET reward=$slot_reward WHERE slot='$check_slot'"
	done
	local stake_reward=0
	local slot_rewards=`sqlite3 "$sqlite_db" "SELECT SUM(reward) FROM leader_slots WHERE epoch=$current_epoch"`
	if [ ! -n "$slot_rewards" ]; then
		local slot_rewards=0
	fi
	local costs=`bc <<< "$credits*0.000005" 2>/dev/null`
	local profit=`bc <<< "scale=3; $stake_reward+$slot_rewards-$costs" 2>/dev/null`
	local profit_usd=`bc <<< "scale=3; $profit*$solana_price/1" 2>/dev/null`
	
	printf "solana,host=%q,identity=$identity_address,epoch=$current_epoch epoch_progress=$epoch_progress,epoch_end_time=$epoch_end_time,leader_slot_time=$leader_slot_time,status=\"$status\",version=\"$version\",validator_commission=$validator_commission,identity_balance=$identity_balance,vote_balance=$vote_balance,solana_price=$solana_price,total_slots=$total_slots,passed_slots=$passed_slots,skipped_slots=$skipped_slots,validator_skip_rate=$validator_skip_rate,cluster_skip_rate=$cluster_skip_rate,credits=$credits,stake=$stake,stake_reward=$stake_reward,slot_rewards=$slot_rewards,costs=$costs,profit=$profit,profit_usd=$profit_usd\n" "$host"
	
	local previous_epoch_info=`curl -sG "$influxdb_url/query" --data-urlencode "u=$influxdb_user" --data-urlencode "p=$influxdb_password" --data-urlencode "db=$influxdb_database" --data-urlencode "epoch=ns" --data-urlencode "q=SELECT host, identity, epoch, solana_price, last(stake_reward) AS stake_reward, slot_rewards, costs FROM solana WHERE \"host\" =~ /^$host\$/ AND epoch='$((current_epoch-1))'" | jq ".results[0].series[0].values"`
	if [ "$previous_epoch_info" != "null" ]; then
		local q_time=`jq ".[0][0]" <<< "$previous_epoch_info"`
		local q_host=`jq ".[0][1]" <<< "$previous_epoch_info" | tr -d '"'`
		local q_identity=`jq ".[0][2]" <<< "$previous_epoch_info" | tr -d '"'`
		local q_epoch=`jq ".[0][3]" <<< "$previous_epoch_info" | tr -d '"'`
		local q_solana_price=`jq ".[0][4]" <<< "$previous_epoch_info"`
		local q_stake_reward=`jq ".[0][5]" <<< "$previous_epoch_info"`
		local q_slot_rewards=`jq ".[0][6]" <<< "$previous_epoch_info"`
		local q_costs=`jq ".[0][7]" <<< "$previous_epoch_info"`
		if [ "$q_stake_reward" -eq 0 2>/dev/null ]; then
			local q_stake_reward=`$daemon vote-account $vote_address --with-rewards | grep -A2 "Epoch Rewards:" | tail -1 | awk '{print $3}' | grep -oE '[0-9]+.[0-9]+'`
			local q_profit=`bc <<< "scale=3; $q_stake_reward+$q_slot_rewards-$q_costs" 2>/dev/null`
			local q_profit_usd=`bc <<< "scale=3; $q_profit*$q_solana_price/1" 2>/dev/null`
			printf "solana,host=%q,identity=$q_identity,epoch=$q_epoch stake_reward=$q_stake_reward,profit=$q_profit,profit_usd=$q_profit_usd $q_time\n" "$q_host"
		fi
	fi
}

main