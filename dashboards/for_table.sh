#!/bin/bash
main() {
	local host=`grep "hostname" /etc/telegraf/telegraf.conf | grep -oPm1 "(?<=\")([^%]+)(?=\")"`
	local ip=`wget -qO- eth0.me`
	local n_cpus=`grep processor /proc/cpuinfo | wc -l`
	
	local ram_total=`bc -l <<< "$(grep "MemTotal" /proc/meminfo | awk '{printf $2}')*1024"`
	local ram_free=`bc -l <<< "$(grep "MemFree" /proc/meminfo | awk '{printf $2}')*1024"`
	local ram_buffers=`bc -l <<< "$(grep "Buffers" /proc/meminfo | awk '{printf $2}')*1024"`
	local ram_cached=`bc -l <<< "$(grep "^Cached" /proc/meminfo | awk '{printf $2}')*1024"`
	
	local drives_info=`df -t simfs -t ext2 -t ext3 -t ext4 -t btrfs -t xfs -t vfat -t ntfs -t swap --total 2>/dev/null | grep total`
	local drive_total=`bc -l <<< "$(awk '{ print $2 }' <<< "$drives_info")*1024"`
	local drive_used=`bc -l <<< "$(awk '{ print $3 }' <<< "$drives_info")*1024"`
	local drive_available=`bc -l <<< "$(awk '{ print $4 }' <<< "$drives_info")*1024"`
	
	local load15=`awk '{printf $3}' /proc/loadavg`
	
	local cpu_info=`grep "cpu " /proc/stat`
	local time_user_1=`awk '{printf $2}' <<< "$cpu_info"`
	local time_nice_1=`awk '{printf $3}' <<< "$cpu_info"`
	local time_system_1=`awk '{printf $4}' <<< "$cpu_info"`
	local time_idle_1=`awk '{printf $5}' <<< "$cpu_info"`
	sleep 1
	local cpu_info=`grep "cpu " /proc/stat`
	local time_user_2=`awk '{printf $2}' <<< "$cpu_info"`
	local time_nice_2=`awk '{printf $3}' <<< "$cpu_info"`
	local time_system_2=`awk '{printf $4}' <<< "$cpu_info"`
	local time_idle_2=`awk '{printf $5}' <<< "$cpu_info"`
	
	local time_user_d=$((time_user_2-time_user_1))
	local time_nice_d=$((time_nice_2-time_nice_1))
	local time_system_d=$((time_system_2-time_system_1))
	local time_idle_d=$((time_idle_2-time_idle_1))
	local time_total=$((time_user_d+time_nice_d+time_system_d+time_idle_d))
	
	local cpu_usage_percent=`bc -l <<< "($time_total-$time_idle_d)/$time_total*100"`
	local ram_used_percent=`bc -l <<< "($ram_total-$ram_free-$ram_buffers-$ram_cached)/$ram_total*100"`
	local drive_used_percent=`bc -l <<< "$drive_used/($drive_used+$drive_available)*100"`
	printf "for_table,host=%q,ip=$ip n_cpus=$n_cpus,ram_total=$ram_total,drive_total=$drive_total,load15=$load15,cpu_usage_percent=$cpu_usage_percent,ram_used_percent=$ram_used_percent,drive_used_percent=$drive_used_percent\n" "$host"
}

main