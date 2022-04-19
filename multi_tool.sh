#!/bin/bash
# Default variables
grafana_action="false"
grafana_user="admin"
grafana_password="admin"

influxdb_action="false"
admin_password=""
reader_password=""

telegraf_action="false"
server_name=""
influxdb_url="http://localhost:8086"

json_file="$HOME/dashboard.json"
json_url=""

function="install"
completely="false"

# Options
. <(wget -qO- https://raw.githubusercontent.com/SecorD0/utils/main/colors.sh) --
option_value(){ echo "$1" | sed -e 's%^--[^=]*=%%g; s%^-[^=]*=%%g'; }
while test $# -gt 0; do
	case "$1" in
	-h|--help)
		. <(wget -qO- https://raw.githubusercontent.com/SecorD0/utils/main/logo.sh)
		echo
		echo -e "${C_LGn}Functionality${RES}: the script performs many actions related to a monitoring (InfluxDB + Telegraf + Grafana)"
		echo
		echo -e "${C_LGn}Usage${RES}: script ${C_LGn}[OPTIONS]${RES}"
		echo
		echo -e "${C_LGn}Options${RES}:"
		echo -e "  -h,  --help        show the help page"
		echo -e "  -g,  --grafana     install Grafana"
		echo -e "  -gu                Grafana panel user (default is ${C_LGn}${grafana_user}${RES})"
		echo -e "  -gp                Grafana panel password (default is ${C_LGn}${grafana_password}${RES})"
		echo -e "  -i,  --influxdb    install InfluxDB"
		echo -e "  -ap                InfluxDB administrator password (default is ${C_LGn}generated${RES})"
		echo -e "  -rp                InfluxDB reader password (default is ${C_LGn}generated${RES})"
		echo -e "  -t,  --telegraf    install Telegraf"
		echo -e "  -sn                server name for Telegraf config"
		echo -e "  -iu                InfluxDB URL to connect Telegraf (default is ${C_LGn}${influxdb_url}${RES})"
		echo -e "  -id                import Grafana dashboard from ${json_file} or from URL"
		echo -e "  -ju                raw JSON dashboard URL"
		echo -e "  -un, --uninstall   uninstall specified program(s) (must be used with one or more -g, -i, -t options)"
		echo -e "  -c,  --completely  delete all data"
		echo
		echo -e "${C_LGn}Useful URLs${RES}:"
		echo -e "https://github.com/SecorD0/Monitoring/blob/main/multi_tool.sh — script URL"
		echo -e "https://teletype.in/@letskynode/Monitoring — Russian-language article about a monitoring"
		echo -e "https://t.me/letskynode — node Community"
		echo -e "https://teletype.in/@letskynode — guides and articles"
		echo
		return 0 2>/dev/null; exit 0
		;;
	-g|--grafana)
		grafana_action="true"
		shift
		;;
	-gu*)
		if ! grep -q "=" <<< "$1"; then shift; fi
		grafana_user=`option_value "$1"`
		shift
		;;
	-gp*)
		if ! grep -q "=" <<< "$1"; then shift; fi
		grafana_password=`option_value "$1"`
		shift
		;;
	-i|--influxdb)
		influxdb_action="true"
		shift
		;;
	-ap*)
		if ! grep -q "=" <<< "$1"; then shift; fi
		admin_password=`option_value "$1"`
		shift
		;;
	-rp*)
		if ! grep -q "=" <<< "$1"; then shift; fi
		reader_password=`option_value "$1"`
		shift
		;;
	-t|--telegraf)
		telegraf_action="true"
		shift
		;;
	-sn*)
		if ! grep -q "=" <<< "$1"; then shift; fi
		server_name=`option_value "$1"`
		shift
		;;
	-iu*)
		if ! grep -q "=" <<< "$1"; then shift; fi
		influxdb_url=`option_value "$1"`
		shift
		;;
	-id)
		function="import_dashboard"
		shift
		;;
	-ju*)
		if ! grep -q "=" <<< "$1"; then shift; fi
		json_url=`option_value "$1"`
		shift
		;;
	-un|--uninstall)
		function="uninstall"
		shift
		;;
	-c|--completely)
		completely="true"
		shift
		;;
	*|--)
		break
		;;
	esac
done

# Functions
printf_n(){ printf "$1\n" "${@:2}"; }
install_grafana() {
	if docker inspect grafana 2>&1 | grep -q "No such object"; then
		printf_n "${C_LGn}Grafana installation...${RES}"
		. <(wget -qO- https://raw.githubusercontent.com/SecorD0/utils/main/installers/docker.sh)
		docker run -dit --name grafana -p 3000:3000 -u root -e "GF_SECURITY_ADMIN_USER=$grafana_user" -e "GF_SECURITY_ADMIN_PASSWORD=$grafana_password" -e "GF_INSTALL_PLUGINS=" -v $HOME/.monitoring/grafana:/var/lib/grafana grafana/grafana
		sleep 10
		docker rm -f grafana
		docker run -dit --name grafana -p 3000:3000 -u root -v $HOME/.monitoring/grafana:/var/lib/grafana grafana/grafana
		. <(wget -qO- https://raw.githubusercontent.com/SecorD0/utils/main/logo.sh)
		printf_n "
The Grafana was ${C_LGn}started${RES}.

Panel URL: ${C_LGn}http://`wget -qO- eth0.me`:3000/${RES}
User: ${C_LGn}${grafana_user}${RES}
Password: ${C_LGn}${grafana_password}${RES}
"
	else
		printf_n "${C_LR}Grafana is already running!${RES}"
	fi
}
install_influxdb() {
	if docker inspect influxdb 2>&1 | grep -q "No such object"; then
		printf_n "${C_LGn}InfluxDB installation...${RES}"
		. <(wget -qO- https://raw.githubusercontent.com/SecorD0/utils/main/installers/docker.sh)
		sudo apt update
		sudo apt upgrade -y
		sudo apt install wget pwgen -y
		if [ ! -n "$admin_password" ]; then admin_password=`pwgen -s 16 1`; fi
		docker run -dit --restart always --name influxdb -p 8083:8083 -p 8086:8086 -e "INFLUXDB_DB=telegraf" -e "INFLUXDB_HTTP_AUTH_ENABLED=true" -e "INFLUXDB_ADMIN_USER=admin" -e "INFLUXDB_ADMIN_PASSWORD=$admin_password" -v $HOME/.monitoring/influxdb:/var/lib/influxdb influxdb:1.8-alpine
		sleep 10
		docker rm -f influxdb
		docker run -dit --restart always --name influxdb -p 8083:8083 -p 8086:8086 -e "INFLUXDB_HTTP_AUTH_ENABLED=true" -v $HOME/.monitoring/influxdb:/var/lib/influxdb influxdb:1.8-alpine
		. <(wget -qO- https://raw.githubusercontent.com/SecorD0/utils/main/miscellaneous/insert_variable.sh) -n influx -v "docker exec -it influxdb influx" -a
		. <(wget -qO- https://raw.githubusercontent.com/SecorD0/utils/main/miscellaneous/insert_variable.sh) -n influxd -v "docker exec -it influxdb influxd" -a
		. <(wget -qO- https://raw.githubusercontent.com/SecorD0/utils/main/miscellaneous/insert_variable.sh) -n influxdb_log -v "docker logs influxdb -fn 100" -a
		if [ ! -n "$reader_password" ]; then reader_password=`pwgen -s 16 1`; fi
		docker exec -it influxdb influx -username admin -password "$admin_password" -database telegraf -execute "CREATE USER reader WITH PASSWORD '$reader_password'; GRANT READ ON telegraf TO reader"
		docker exec -it influxdb influx -username admin -password "$admin_password" -database telegraf -execute 'ALTER RETENTION POLICY "autogen" ON "telegraf" DURATION 7d'
		sudo tee <<EOF >/dev/null /etc/cron.daily/influxdb_restart
#!/bin/sh
docker restart influxdb
EOF
		chmod +x /etc/cron.daily/influxdb_restart
		. <(wget -qO- https://raw.githubusercontent.com/SecorD0/utils/main/logo.sh)
		printf_n "
The InfluxDB was ${C_LGn}started${RES}.

Connection URL: ${C_LGn}http://`wget -qO- eth0.me`:8086/${RES}

User: ${C_LGn}admin${RES}
Password: ${C_LGn}${admin_password}${RES}

User: ${C_LGn}reader${RES}
Password: ${C_LGn}${reader_password}${RES}
"
	else
		printf_n "${C_LR}InfluxDB is already running!${RES}"
	fi
}
install_telegraf() {
	if sudo systemctl status telegraf 2>&1 | grep -q "could not be found"; then
		printf_n "${C_LGn}Telegraf installation...${RES}"
		if [ ! -n "$server_name" ]; then
			printf_n "${C_R}You didn't specify the sever name via -sn option!${RES}"
			return 1 2>/dev/null; exit 1
		fi
		if [ ! -n "$admin_password" ]; then
			printf_n "${C_R}You didn't specify the admin password via -ap option!${RES}"
			return 1 2>/dev/null; exit 1
		fi
		mkdir -p $HOME/.monitoring/telegraf/
		. /etc/*-release
		echo "deb https://repos.influxdata.com/${DISTRIB_ID,,} ${DISTRIB_CODENAME} stable" > /etc/apt/sources.list.d/influxdb.list
		wget -qO- https://repos.influxdata.com/influxdb.key | sudo apt-key add -
		sudo apt update
		sudo apt upgrade -y
		sudo apt install wget nano bc jq telegraf subversion -y
		sudo tee <<EOF >/dev/null /etc/telegraf/telegraf.conf
[agent]
  interval = "20s"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "0s"
  flush_interval = "10s"
  flush_jitter = "0s"
  precision = ""
  hostname = "$server_name"
  omit_hostname = false

[[outputs.influxdb]]
  urls = ["$influxdb_url"]
  database = "telegraf"
  timeout = "5s"
  username = "admin"
  password = "$admin_password"

[[inputs.cpu]]
  interval = "5s"
  percpu = true
  totalcpu = true
  collect_cpu_time = false
  report_active = false

[[inputs.mem]]
  interval = "5s"

[[inputs.disk]]
  ignore_fs = ["tmpfs", "devtmpfs", "devfs", "iso9660", "overlay", "aufs", "squashfs"]

[[inputs.net]]
  interfaces = ["eth0"]

[[inputs.docker]]
  container_state_include = ["created", "restarting", "running", "removing", "paused", "exited", "dead"]
  perdevice = false
  total = true

#[[inputs.procstat]]
  #pid_tag = true
  #pattern = "massa*|minima*|evmos*"

#[[inputs.systemd_units]]
  #pattern = "massad.service minima_9001.service evmosd.service"

[[inputs.exec]]
  interval = "5s"
  commands = ["sudo su -c /root/.monitoring/telegraf/for_table.sh -s /bin/bash root"]
  data_format = "influx"

[[inputs.netstat]]
[[inputs.diskio]]
[[inputs.kernel]]
[[inputs.processes]]
[[inputs.swap]]
[[inputs.system]]

EOF
		svn export --force https://github.com/SecorD0/Monitoring/trunk/dashboards/for_table.sh $HOME/.monitoring/telegraf/
		chmod +x $HOME/.monitoring/telegraf/for_table.sh
		rm -rf $HOME/.monitoring/telegraf/telegraf.conf
		ln -s /etc/telegraf/telegraf.conf $HOME/.monitoring/telegraf/telegraf.conf
		sudo usermod -aG docker telegraf
		sudo -- bash -c 'echo "telegraf ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers'
		sudo systemctl restart telegraf
		. <(wget -qO- https://raw.githubusercontent.com/SecorD0/utils/main/miscellaneous/insert_variable.sh) -n telegraf_log -v "sudo journalctl -fn 100 -u telegraf" -a
		. <(wget -qO- https://raw.githubusercontent.com/SecorD0/utils/main/logo.sh)
		printf_n "
The Telegraf was ${C_LGn}started${RES}.
"
	else
		printf_n "${C_LR}Telegraf is already installed!${RES}"
	fi
}
import_dashboard() {
	if [ ! -f "$json_file" ]; then
		if [ ! -n "$json_url" ]; then
			printf_n "${C_R}You didn't specify JSON dashboard format URL via -ju option!${RES}"
			return 1 2>/dev/null; exit 1
		else
			sudo apt install curl -y &>/dev/null
			echo '{"dashboard": '`wget -qO- "$json_url" | tr -d '\r'`', "folderId": 0, "overwrite": false}}' > $HOME/dashboard.json
		fi
	else
		echo '{"dashboard": '`cat "$json_file" | tr -d '\r'`', "folderId": 0, "overwrite": false}}' > $HOME/dashboard.json
	fi
	
	local grafana_user=""
	if [ ! -n "$grafana_user" ]; then
		printf "${C_LGn}Enter the Grafana username:${RES} "
		local grafana_user
		read -r grafana_user
	fi
	if [ ! -n "$grafana_user" ]; then
		printf_n "${C_R}You didn't specify the Grafana username!${RES}"
		return 1 2>/dev/null; exit 1
	fi
	
	local grafana_password=""
	if [ ! -n "$grafana_password" ]; then
		printf "${C_LGn}Enter the Grafana user password:${RES} "
		local grafana_password
		read -r grafana_password
	fi
	if [ ! -n "$grafana_password" ]; then
		printf_n "${C_R}You didn't specify the Grafana user password!${RES}"
		return 1 2>/dev/null; exit 1
	fi
	
	printf_n
	local response=`curl -su "${grafana_user}:${grafana_password}" -XPOST "http://localhost:3000/api/dashboards/db" -H "Content-Type: application/json" -d @$HOME/dashboard.json`
	if grep -q '"status":"success"' <<< "$response"; then
		printf_n "${C_LGn}Done!${RES}"
	else
		printf_n "${C_R}There is an error!${RES}\n"
		jq <<< "$response"
	fi
	rm -rf $HOME/dashboard.json
}
uninstall() {
	if [ "$grafana_action" == "true" ]; then
		printf_n "${C_LR}Grafana uninstalling...${RES}"
		docker stop grafana
		docker rm grafana
		docker rmi grafana/grafana
		if [ "$completely" == "true" ]; then
			rm -rf $HOME/.monitoring/grafana
		fi
	fi
	if [ "$influxdb_action" == "true" ]; then
		printf_n "${C_LR}InfluxDB uninstalling...${RES}"
		docker stop influxdb
		docker rm influxdb
		docker rmi influxdb:1.8-alpine
		. <(wget -qO- https://raw.githubusercontent.com/SecorD0/utils/main/miscellaneous/insert_variable.sh) -n influx -da
		. <(wget -qO- https://raw.githubusercontent.com/SecorD0/utils/main/miscellaneous/insert_variable.sh) -n influxdb_log -da
		rm -rf /etc/cron.daily/influxdb_restart
		if [ "$completely" == "true" ]; then
			rm -rf $HOME/.monitoring/influxdb
		fi
	fi
	if [ "$telegraf_action" == "true" ]; then
		printf_n "${C_LR}Telegraf uninstalling...${RES}"
		sudo systemctl stop telegraf
		sudo systemctl disable telegraf
		sudo apt purge telegraf -y
		. <(wget -qO- https://raw.githubusercontent.com/SecorD0/utils/main/miscellaneous/insert_variable.sh) -n telegraf_log -da
		rm -rf /etc/apt/sources.list.d/influxdb.list
		if [ "$completely" == "true" ]; then
			sudo userdel -rf telegraf
			rm -rf $HOME/.monitoring/telegraf /etc/telegraf/
		fi
	fi
	rmdir $HOME/.monitoring/
	printf_n "${C_LGn}Done!${RES}"
}

# Actions
sudo apt install wget -y &>/dev/null
. <(wget -qO- https://raw.githubusercontent.com/SecorD0/utils/main/logo.sh)

if [ "$grafana_action" == "false" ] && [ "$influxdb_action" == "false" ] && [ "$telegraf_action" == "false" ] && [ "$function" != "import_dashboard" ]; then
	printf_n "${C_R}You didn't select the software for an action! View help page via -h option!${RES}"
	return 1 2>/dev/null; exit 1
fi

if [ "$function" == "install" ]; then
	mkdir -p $HOME/.monitoring
	if [ "$grafana_action" == "true" ]; then
		install_grafana
	fi
	if [ "$influxdb_action" == "true" ]; then
		install_influxdb
	fi
	if [ "$telegraf_action" == "true" ]; then
		install_telegraf
	fi
else
	$function
fi
