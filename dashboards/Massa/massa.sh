#!/bin/bash
# Config
client_dir="$HOME/massa/massa-client/"

# Functions
main() {
	local host=`grep "hostname" /etc/telegraf/telegraf.conf | grep -oPm1 "(?<=\")([^%]+)(?=\")"`
	cd "$client_dir"
	if grep -q "check if your node is running" <<< `./massa-client get_status`; then
		local status="Not running"
		printf "massa,host=%q status=\"$status\"\n" "$host"
		exit 0
	fi
	local status="Running"
	
	local wallet_info=`./massa-client -j wallet_info`
	local main_address=`jq -r "[.[]] | .[0].address_info.address" <<< "$wallet_info"`
	local wallet_info=`jq ".\"$main_address\"" <<< "$wallet_info"`
	local node_info=`./massa-client -j get_status | jq`
	
	local current_cycle=`jq -r ".current_cycle" <<< "$node_info"`
	local node_id=`jq -r ".node_id" <<< "$node_info"`
	
	local episode_remaining_time=`./massa-client when_episode_ends | grep -oPm1 "(?<=^)([^%]+)(?= remaining)"`
	local days_remaining=`grep -oE "[0-9]+ day" <<< "$episode_remaining_time" | grep -oE '[0-9]+'`
	local hours_remaining=`grep -oE "[0-9]+ hour" <<< "$episode_remaining_time" | grep -oE '[0-9]+'`
	local minutes_remaining=`grep -oE "[0-9]+ minute" <<< "$episode_remaining_time" | grep -oE '[0-9]+'`
	local seconds_remaining=`grep -oE "[0-9]+ second" <<< "$episode_remaining_time" | grep -oE '[0-9]+'`
	if [ ! -n "$days_remaining" ]; then local days_remaining=0; fi
	if [ ! -n "$hours_remaining" ]; then local hours_remaining=0; fi
	if [ ! -n "$minutes_remaining" ]; then local minutes_remaining=0; fi
	if [ ! -n "$seconds_remaining" ]; then local seconds_remaining=0; fi
	local episode_end_time=`bc <<< "($(date +%s)+$days_remaining*86400+$hours_remaining*3600+$minutes_remaining*60+$seconds_remaining)*1000"`
	
	local version=`jq -r ".version" <<< "$node_info"`
	local opened_ports=`ss -tulpn | grep :3303`
	if [ -n "$opened_ports" ]; then
		local opened_ports="Yes"
	else
		local opened_ports="No"
	fi
	
	local staking_addresses=`./massa-client -j node_get_staking_addresses`
	if grep -q "$main_address" <<< "$staking_addresses"; then
		local registered_for_staking="Yes"
	else
		local registered_for_staking="No"
	fi
	
	local wallet_balance=`jq -r ".address_info.balance.candidate_ledger_info.balance" <<< "$wallet_info"`
	local total_rolls=`jq -r ".address_info.rolls.candidate_rolls" <<< "$wallet_info"`
	local active_rolls=`jq -r ".address_info.rolls.active_rolls" <<< "$wallet_info"`
	
	printf "massa,cycle=$current_cycle,host=%q,node_id=$node_id episode_end_time=$episode_end_time,status=\"$status\",version=\"$version\",opened_ports=\"$opened_ports\",registered_for_staking=\"$registered_for_staking\",wallet_balance=$wallet_balance,total_rolls=$total_rolls,active_rolls=$active_rolls\n" "$host"
}

main