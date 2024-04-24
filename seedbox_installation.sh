#!/bin/bash

# Helper functions for setting styles and printing messages
setStyle() {
    tput sgr0; tput setaf "$1"; [[ "$2" == "bold" ]] && tput bold
}

printMessage() {
    setStyle "$2" "$3"
    echo "$1"
    tput sgr0
}

printInfoMessage() { printMessage "$1" 2 bold; }
printIndentedInfoMessage() { printMessage "    $1" 2; }
printOverwriteInfoMessage() { printMessage "$1" 2; }
printDimMessage() { printMessage "$1" 7 dim; }
printInputPrompt() { printMessage "$1" 6 bold; }
printWarningMessage() { printMessage "$1" 3; }
printErrorMessage() { printMessage "$1" 1 bold; }
printErrorAndExit() { printErrorMessage "$1"; exit 1; }

# Overwrites the current line with an info message, using cyan text
printOverwriteInfoMessage() {
    tput sgr0; tput setaf 6    # Reset style and set foreground to cyan
    echo -en "\r\e[K$1"        # `\r` moves to the start, `\e[K` clears the line
    tput sgr0                  # Reset the terminal formatting to default
}

# Overwrites the current line with an error message, using maroon red background and white text, outputs to stderr
printOverwriteErrorMessage() {
    tput sgr0; tput setab 196; tput setaf 7; tput bold  # Reset style, set background to dark red, foreground to white, and make text bold
    echo -en  "\r\e[K$1" >&2                            # `\r` moves to the start, `\e[K` clears the line, redirect output to stderr
    tput sgr0                                           # Reset the terminal formatting to default
}

# Function to print a separator line
separator() {
    echo -e "\n"
    echo $(printf '%*s' "$(tput cols)" | tr ' ' '=')
    echo -e "\n"
}

# Function: Update System and Install Dependencies
update_and_install_dependencies() {
    local dependencies=("sudo" "curl" "sysstat" "psmisc" "python3" "python3-pip" "python3-requests" "python3-psutil" "python3-apscheduler" "screen" "tzdata")
    apt-get -qq update && apt-get -qqy upgrade

    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            apt-get install "$dep" -qqy || printErrorAndExit "$dep Installation Failed"
        fi
    done
}

install_autobrr_() {
	if [ -z $username ]; then	# return if $username is not Set
		printErrorMessage "Username not set"
		return 1
	fi
	if [ -z $(getent passwd $username) ]; then	# return if username does not exist
		printErrorMessage "User does not exist"
		return 1
	fi
	if [[ -z $autobrr_port ]]; then
		printErrorMessage "AutoBrr port not set"
		autobrr_port=7474
	fi
	## Install AutoBrr
	# Check CPU architecture
	if [ $(uname -m) == "x86_64" ]; then
		curl -sL $(curl -s https://api.github.com/repos/autobrr/autobrr/releases/latest | grep browser_download_url | grep linux_x86_64 | cut -d '"' -f 4) -o autobrr_linux_x86_64.tar.gz
	elif [ $(uname -m) == "aarch64" ]; then
		curl -sL $(curl -s https://api.github.com/repos/autobrr/autobrr/releases/latest | grep browser_download_url | grep linux_arm64.tar | cut -d '"' -f 4) -o autobrr_linux_arm64.tar.gz
	else
		printErrorMessage "AutoBrr download failed"
		return 1
	fi
	# Exit if download fail
	if [ ! -f autobrr*.tar.gz ]; then
		printErrorMessage "AutoBrr download failed"
		return 1
	fi
	sudo tar -C /usr/bin -xzf autobrr*.tar.gz
	# Exit if extraction fail
	if [ $? -ne 0 ]; then
		printErrorMessage "AutoBrr extraction failed"
		rm autobrr*.tar.gz
		return 1
	fi
	mkdir -p /home/$username/.config/autobrr
	secret_session_key=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c16)
	cat << EOF >/home/$username/.config/autobrr/config.toml
host = "0.0.0.0"

port = $autobrr_port

logLevel = "DEBUG"

checkForUpdates = true

sessionSecret = "$secret_session_key"

EOF
	chown -R $username /home/$username/.config/autobrr
	# Create AutoBrr service
	touch /etc/systemd/system/autobrr@.service
	cat << EOF >/etc/systemd/system/autobrr@.service
[Unit]
Description=autobrr service
After=syslog.target network-online.target

[Service]
Type=simple
User=$username
Group=$username
ExecStart=/usr/bin/autobrr --config=/home/$username/.config/autobrr/

[Install]
WantedBy=multi-user.target
EOF
	# Enable and start AutoBrr
	systemctl enable autobrr@$username
	systemctl start autobrr@$username
	# Clean up
	rm autobrr*.tar.gz
	
	# Check if AutoBrr is running
	if [ -z $(pgrep autobrr) ]; then
		printErrorMessage "AutoBrr failed to start"
		return 1
	fi

	return 0
}

install_vertex_() {
	if [[ -z $username ]] || [ -z $password ]; then
		printErrorMessage "Username or password not set"
		return 1
	fi
	if [[ -z $vertex_port ]]; then
		printErrorMessage "Vertex port not set"
		vertex_port=3000
	fi
	#Check if docker is installed
	if [ -z $(which docker) ]; then
		curl -fsSL https://get.docker.com -o get-docker.sh
		# Check if download fail
		if [ ! -f get-docker.sh ]; then
			printErrorMessage "Docker download failed"
			return 1
		fi
		sh get-docker.sh
		# Check for installation failure.
		if [ $? -ne 0 ]; then
			printErrorMessage "Docker installation failed"
			rm get-docker.sh
			return 1
		fi
	else
		#Check if Docker image vertex is installed
		if [ -n $(docker images | grep vertex | grep -v grep) ]; then
			printErrorMessage "Vertex already installed"
			return 1
		fi
	fi
	## Install Vertex
	if [ -z $(which apparmor) ]; then
		apt-get -y install apparmor
		#Check if install is successful
		if [ $? -ne 0 ]; then
			printErrorMessage "Apparmor Installation Failed"
			return 1
		fi
	fi
	if [ -z $(which apparmor-utils) ]; then
		apt-get -y install apparmor-utils
		#Check if install is successful
		if [ $? -ne 0 ]; then
			printErrorMessage "Apparmor-utils Installation Failed"
			return 1
		fi
	fi
	timedatectl set-timezone Asia/Singapore
	mkdir -p /opt/seedbox/vertex
	chmod 755 /opt/seedbox/vertex
	docker run -d --name vertex --restart unless-stopped -v /opt/seedbox/vertex:/vertex -p $vertex_port:3000 -e TZ=Asia/Singapore lswl/vertex:stable
	sleep 5s
	# Check if Vertex is running
	if ! [ "$( docker container inspect -f '{{.State.Status}}' vertex )" = "running" ]; then
		printErrorMessage "Vertex failed to start"
		return 1
	fi
	# Set username & password
	docker stop vertex
	sleep 5s
	# Confirm the Docker container named 'vertex' is stopped
	if ! [ "$( docker container inspect -f '{{.State.Status}}' vertex )" = "exited" ]; then
		printErrorMessage "Vertex failed to stop"
		return 1
	fi
	# Set username & password
	vertex_pass=$(echo -n $password | md5sum | awk '{print $1}')
	cat << EOF >/opt/seedbox/vertex/data/setting.json
{
  "username": "$username",
  "password": "$vertex_pass"
}
EOF
	# Start Vertex
	docker start vertex
	sleep 5s
	# Check if Vertex has restarted
	if ! [ "$( docker container inspect -f '{{.State.Status}}' vertex )" = "running" ]; then
		printErrorMessage "Vertex failed to start"
		return 1
	fi
	# Clean up
	rm get-docker.sh
	return 0
}

install_autoremove-torrents_() {
	if [[ -z $username ]] || [ -z $password ]; then
		printErrorMessage "Username or password not set"
		return 1
	fi
	if [[ -z $qb_port ]]; then
		printErrorMessage "qBittorrent port not set"
		qb_port=8080
	fi
	if [ -f /home/$username/.config.yml ]; then
		printErrorMessage "Autoremove-torrents already installed"
		return 1
	fi
	## Install Autoremove-torrents
	if [ -z $(which pipx) ]; then
		apt-get install pipx -y
		#Check if install is successful
		if [ $? -ne 0 ]; then
			printErrorMessage "Pipx Installation Failed"
			#Alternative method
			apt-get -qqy install python3-distutils python3-apt
			[[ $(pip --version) ]] || (apt-get -qqy install curl && curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py && python3 get-pip.py && rm get-pip.py )
			pip -q install autoremove-torrents
			# Check for installation failure.
			if [ $? -ne 0 ]; then
				printErrorMessage "Autoremove-torrents installation failed"
				return 1
			fi
		else
			su $username -s /bin/sh -c "pipx install autoremove-torrents"
			# Check for installation failure.
			if [ $? -ne 0 ]; then
				printErrorMessage "Autoremove-torrents installation failed"
				return 1
			fi
			su user -s /bin/sh -c "pipx ensurepath"
		fi
	fi
	

    # qBittorrent
	if test -f /usr/bin/qbittorrent-nox; then
		touch /home/$username/.config.yml && chown $username:$username /home/$username/.config.yml
        cat << EOF >>/home/$username/.config.yml
General-qb:          
  client: qbittorrent
  host: http://127.0.0.1:$qb_port
  username: $username
  password: $password
  strategies:
    General:
      seeding_time: 3153600000
  delete_data: true
EOF
    fi
	sed -i 's+127.0.0.1: +127.0.0.1:+g' $HOME/.config.yml
    mkdir -p /home/$username/.autoremove-torrents/log && chown -R $username /home/$username/.autoremove-torrents
	touch /home/$username/.autoremove-torrents/autoremove-torrents.sh && chown $username:$username /home/$username/.autoremove-torrents/autoremove-torrents.sh
	cat << EOF >/home/$username/.autoremove-torrents/autoremove-torrents.sh
#!/bin/bash
while true; do
	/home/user/.local/bin/autoremove-torrents --conf=/home/$username/.config.yml --log=/home/$username/.autoremove-torrents/log
	sleep 5s
done
EOF
	chmod +x /home/$username/.autoremove-torrents/autoremove-torrents.sh
	# Create Autoremove-torrents service
	touch /etc/systemd/system/autoremove-torrents@.service
	cat << EOF >/etc/systemd/system/autoremove-torrents@.service
[Unit]
Description=autoremove-torrents service
After=syslog.target network-online.target

[Service]
Type=simple
User=$username
Group=$username
ExecStart=/home/$username/.autoremove-torrents/autoremove-torrents.sh

[Install]
WantedBy=multi-user.target
EOF
	# Enable and start Autoremove-torrents
	systemctl enable autoremove-torrents@$username
	systemctl start autoremove-torrents@$username
	return 0
}

## System Tweaking

# Tuned
tuned_() {
    if [ -z $(which tuned) ]; then
		apt-get -qqy install tuned
		#Check if install is successful
		if [ $? -ne 0 ]; then
			printErrorMessage "Tuned Installation Failed"
			return 1
		fi
	fi
	return 0
}

# Network
set_ring_buffer_() {
    interface=$(ip -o -4 route show to default | awk '{print $5}')
	if [ -z $(which ethtool) ]; then
		apt-get -y install ethtool
		if [ $? -ne 0 ]; then
			printErrorMessage "Ethtool Installation Failed"
			return 1
		fi
	fi
    ethtool -G $interface rx 1024
	if [ $? -ne 0 ]; then
		printErrorMessage "Ring Buffer Setting Failed"
		return 1
	fi
    sleep 1
    ethtool -G $interface tx 2048
	if [ $? -ne 0 ]; then
		printErrorMessage "Ring Buffer Setting Failed"
		return 1
	fi
    sleep 1
}
set_txqueuelen_() {
	interface=$(ip -o -4 route show to default | awk '{print $5}')
	if [ -z $(which net-tools) ]; then
		apt-get -y install net-tools
		if [ $? -ne 0 ]; then
			printErrorMessage "net-tools Installation Failed"
			return 1
		fi
	fi
    ifconfig $interface txqueuelen 10000
    sleep 1
}
set_initial_congestion_window_() {
    iproute=$(ip -o -4 route show to default)
    ip route change $iproute initcwnd 25 initrwnd 25
}
disable_tso_() {
	interface=$(ip -o -4 route show to default | awk '{print $5}')
	if [ -z $(which ethtool) ]; then
		apt-get -y install ethtool
		if [ $? -ne 0 ]; then
			printErrorMessage "Ethtool Installation Failed"
			return 1
		fi
	fi
	ethtool -K $interface tso off gso off gro off
	sleep 1
	return 0
}


# Drive
set_disk_scheduler_() {
    i=1
    drive=()
    # Retrieve all available drives
    disk=$(lsblk -nd --output NAME)
    # Verify that at least one disk is detected
    if [[ -z $disk ]]; then
        printErrorMessage "Disk not found"
        return 1
    fi
    # Calculate the number of drives
    diskno=$(echo $disk | awk '{print NF}')
    # Store the device names in an array for later iteration
    while [ $i -le $diskno ]
    do
        device=$(echo $disk | awk -v i=$i '{print $i}')
        drive+=($device)
        i=$(( $i + 1 ))
    done
    i=1 x=0
    # Adjust the scheduler settings for each disk based on whether it is an HDD or SSD.
    while [ $i -le $diskno ]
    do
	    diskname=$(eval echo ${drive["$x"]})
	    disktype=$(cat /sys/block/$diskname/queue/rotational)
	    if [ "${disktype}" == 0 ]; then		
		    echo kyber > /sys/block/$diskname/queue/scheduler
	    else
		    echo mq-deadline > /sys/block/$diskname/queue/scheduler
	    fi
    i=$(( $i + 1 )) x=$(( $x + 1 ))
    done
	return 0
}

# File Open Limit
set_file_open_limit_() {
    # Exit the function if the username is not provided
    if [[ -z $username ]]; then
        printErrorMessage "Username not set"
        return 1
    fi
    # Append file open limits for the user to the limits configuration file
    cat << EOF >> /etc/security/limits.conf
# Set hard limit for maximum number of open files
$username hard nofile 1048576
# Set soft limit for maximum number of open files
$username soft nofile 1048576
EOF
    return 0
}

# Kernel Settings
kernel_settings_() {
    # Retrieve total memory in kB
    memory_size=$(grep MemTotal /proc/meminfo | awk '{print $2}')

    # Define upper limits for TCP memory in bytes
    tcp_mem_min_cap=262144    # 1GB
    tcp_mem_pressure_cap=2097152  # 8GB
    tcp_mem_max_cap=4194304  # 16GB

    # Convert memory_size from kB to 4K pages
    memory_4k=$(( memory_size / 4 ))

    # Validate if memory_size was successfully retrieved
    if [ -n "$memory_size" ]; then
        # Set TCP memory based on available memory
        if [ $memory_size -le 524288 ]; then  # If memory is 512MB or less
            tcp_mem_min=$(( memory_4k / 32 ))
            tcp_mem_pressure=$(( memory_4k / 16 ))
            tcp_mem_max=$(( memory_4k / 8 ))
            rmem_max=8388608
            wmem_max=8388608
            win_scale=3
        elif [ $memory_size -le 1048576 ]; then  # If memory is 1GB or less
            tcp_mem_min=$(( memory_4k / 16 ))
            tcp_mem_pressure=$(( memory_4k / 8 ))
            tcp_mem_max=$(( memory_4k / 6 ))
            rmem_max=16777216
            wmem_max=16777216
            win_scale=2
        elif [ $memory_size -le 4194304 ]; then  # If memory is 4GB or less
            tcp_mem_min=$(( memory_4k / 8 ))
            tcp_mem_pressure=$(( memory_4k / 6 ))
            tcp_mem_max=$(( memory_4k / 4 ))
            rmem_max=33554432
            wmem_max=33554432
            win_scale=2
        elif [ $memory_size -le 16777216 ]; then  # If memory is 16GB or less
            tcp_mem_min=$(( memory_4k / 8 ))
            tcp_mem_pressure=$(( memory_4k / 4 ))
            tcp_mem_max=$(( memory_4k / 2 ))
            rmem_max=67108864
            wmem_max=67108864
            win_scale=1
        else  # If memory is more than 16GB
            tcp_mem_min=$(( memory_4k / 8 ))
            tcp_mem_pressure=$(( memory_4k / 4 ))
            tcp_mem_max=$(( memory_4k / 2 ))
            rmem_max=134217728
            wmem_max=134217728
            win_scale=-2
        fi

        # Ensure calculated values do not exceed defined caps
        tcp_mem_min=$(($tcp_mem_min > tcp_mem_min_cap ? tcp_mem_min_cap : tcp_mem_min))
        tcp_mem_pressure=$(($tcp_mem_pressure > tcp_mem_pressure_cap ? tcp_mem_pressure_cap : tcp_mem_pressure))
        tcp_mem_max=$(($tcp_mem_max > tcp_mem_max_cap ? tcp_mem_max_cap : tcp_mem_max))
        tcp_mem="$tcp_mem_min $tcp_mem_pressure $tcp_mem_max"
    else
        printErrorMessage "Memory size not found"
        tcp_mem=$(cat /proc/sys/net/ipv4/tcp_mem)
        tcp_rmem=$(cat /proc/sys/net/ipv4/tcp_rmem)
        tcp_wmem=$(cat /proc/sys/net/ipv4/tcp_wmem)
        rmem_max=$(cat /proc/sys/net/core/rmem_max)
        wmem_max=$(cat /proc/sys/net/core/wmem_max)
        win_scale=$(cat /proc/sys/net/ipv4/tcp_adv_win_scale)
    fi

    # Default memory settings for sockets
    rmem_default=262144
    wmem_default=16384
    tcp_rmem="8192 $rmem_default $rmem_max"
    tcp_wmem="4096 $wmem_default $wmem_max"

    # Validate kernel settings
    if [[ -z $tcp_mem ]] || [[ -z $tcp_rmem ]] || [[ -z $tcp_wmem ]] || [[ -z $rmem_max ]] || [[ -z $wmem_max ]] || [[ -z $win_scale ]]; then
        printErrorMessage "Kernel settings not set"
        return 1
    fi
    cat << EOF >/etc/sysctl.conf
kernel.pid_max = 4194303
kernel.msgmnb = 65536
kernel.msgmax = 65536
kernel.sched_migration_cost_ns = 5000000
kernel.sched_autogroup_enabled = 0
kernel.sched_min_granularity_ns = 10000000
kernel.sched_wakeup_granularity_ns = 15000000

fs.file-max = 1048576
fs.nr_open = 1048576

vm.dirty_background_ratio = 5
vm.dirty_ratio = 30
vm.dirty_expire_centisecs = 1000
vm.dirty_writeback_centisecs = 100
vm.swappiness = 10

net.core.netdev_budget = 50000
net.core.netdev_budget_usecs = 8000
net.core.netdev_max_backlog = 100000
net.core.rmem_default = $rmem_default
net.core.rmem_max = $rmem_max
net.core.wmem_default = $wmem_default
net.core.wmem_max = $wmem_max
net.core.optmem_max = 4194304

net.ipv4.route.mtu_expires = 1800
net.ipv4.route.min_adv_mss = 536
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.ip_no_pmtu_disc = 0
net.ipv4.neigh.default.unres_qlen_bytes = 16777216

net.core.somaxconn = 524288
net.ipv4.tcp_max_syn_backlog = 524288
net.ipv4.tcp_abort_on_overflow = 0
net.ipv4.tcp_max_orphans = 262144
net.ipv4.tcp_max_tw_buckets = 10240
net.ipv4.tcp_mtu_probing = 2
net.ipv4.tcp_base_mss = 1460
net.ipv4.tcp_min_snd_mss = 536
net.ipv4.tcp_sack = 1
net.ipv4.tcp_comp_sack_delay_ns = 250000
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_early_retrans = 3
net.ipv4.tcp_ecn = 0
net.ipv4.tcp_reordering = 10
net.ipv4.tcp_max_reordering = 600
net.ipv4.tcp_synack_retries = 10
net.ipv4.tcp_syn_retries = 7
net.ipv4.tcp_keepalive_time = 7200
net.ipv4.tcp_keepalive_probes = 15
net.ipv4.tcp_keepalive_intvl = 60
net.ipv4.tcp_retries1 = 3
net.ipv4.tcp_retries2 = 10
net.ipv4.tcp_orphan_retries = 2
net.ipv4.tcp_autocorking = 0
net.ipv4.tcp_frto = 0
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_fin_timeout = 5
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_workaround_signed_windows = 1
net.ipv4.tcp_notsent_lowat = 131072
net.ipv4.tcp_limit_output_bytes = 3276800
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    sysctl -p
	return 0
}

# BBR
install_bbrx_() {
	#Check if $OS is Set
	if [[ -z $OS ]]; then
		# Linux Distro Version check
		if [ -f /etc/os-release ]; then
			. /etc/os-release
			OS=$NAME
		elif type lsb_release >/dev/null 2>&1; then
			OS=$(lsb_release -si)
		elif [ -f /etc/lsb-release ]; then
			. /etc/lsb-release
			OS=$DISTRIB_ID
		elif [ -f /etc/debian_version ]; then
			OS=Debian
		else
			OS=$(uname -s)
			VER=$(uname -r)
		fi
	fi
	if [[ "$OS" =~ "Debian" ]]; then
		if [ $(uname -m) == "x86_64" ]; then
			apt-get -y install linux-image-amd64 linux-headers-amd64
			if [ $? -ne 0 ]; then
				printErrorMessage "BBR installation failed"
				return 1
			fi
		elif [ $(uname -m) == "aarch64" ]; then
			apt-get -y install linux-image-arm64 linux-headers-arm64
			if [ $? -ne 0 ]; then
				printErrorMessage "BBR installation failed"
				return 1
			fi
		fi
	elif [[ "$OS" =~ "Ubuntu" ]]; then
		apt-get -y install linux-image-generic linux-headers-generic
		if [ $? -ne 0 ]; then
			printErrorMessage "BBR installation failed"
			return 1
		fi
	else
		printErrorMessage "Unsupported OS"
		return 1
	fi
	curl -sL https://raw.githubusercontent.com/iamnhx/seedbox/main/BBR/BBRx/BBRx.sh -o /opt/seedbox/BBRx.sh && chmod +x /opt/seedbox/BBRx.sh
	# Check if download fail
	if [ ! -f /opt/seedbox/BBRx.sh ]; then
		printErrorMessage "BBR download failed"
		return 1
	fi
    ## Install tweaked BBR automatically on reboot
    cat << EOF > /etc/systemd/system/bbrinstall.service
[Unit]
Description=BBRinstall
After=network.target

[Service]
Type=oneshot
ExecStart=/opt/seedbox/BBRx.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable bbrinstall.service
	return 0
}

install_bbrv3() {
    if [ $(uname -m) == "x86_64" ]; then
        curl -O https://raw.githubusercontent.com/iamnhx/seedbox/main/BBR/BBRv3/x86_64/linux-headers-6.4.0+-amd64.deb
        if [ ! -f linux-headers-6.4.0+-amd64.deb ]; then
            echo "BBRv3 download failed"
            return 1
        fi
        curl -O https://raw.githubusercontent.com/iamnhx/seedbox/main/BBR/BBRv3/x86_64/linux-image-6.4.0+-amd64.deb
        if [ ! -f linux-image-6.4.0+-amd64.deb ]; then
            echo "BBRv3 download failed"
            rm linux-headers-6.4.0+-amd64.deb
            return 1
        fi
        curl -O https://raw.githubusercontent.com/iamnhx/seedbox/main/BBR/BBRv3/x86_64/linux-libc-dev_-6.4.0-amd64.deb
        if [ ! -f linux-libc-dev_-6.4.0-amd64.deb ]; then
            echo "BBRv3 download failed"
            rm linux-headers-6.4.0+-amd64.deb linux-image-6.4.0+-amd64.deb
            return 1
        fi
        apt install ./linux-headers-6.4.0+-amd64.deb ./linux-image-6.4.0+-amd64.deb ./linux-libc-dev_-6.4.0-amd64.deb
        # Clean up
        rm linux-headers-6.4.0+-amd64.deb linux-image-6.4.0+-amd64.deb linux-libc-dev_-6.4.0-amd64.deb
    elif [ $(uname -m) == "aarch64" ]; then
        curl -O https://raw.githubusercontent.com/iamnhx/seedbox/main/BBR/BBRv3/arm64/linux-headers-6.4.0+-arm64.deb
        if [ ! -f linux-headers-6.4.0+-arm64.deb ]; then
            echo "BBRv3 download failed"
            return 1
        fi
        curl -O https://raw.githubusercontent.com/iamnhx/seedbox/main/BBR/BBRv3/arm64/linux-image-6.4.0+-arm64.deb
        if [ ! -f linux-image-6.4.0+-arm64.deb ]; then
            echo "BBRv3 download failed"
            rm linux-headers-6.4.0+-arm64.deb
            return 1
        fi
        curl -O https://raw.githubusercontent.com/iamnhx/seedbox/main/BBR/BBRv3/arm64/linux-libc-dev_-6.4.0-arm64.deb
        if [ ! -f linux-libc-dev_-6.4.0-arm64.deb ]; then
            echo "BBRv3 download failed"
            rm linux-headers-6.4.0+-arm64.deb linux-image-6.4.0+-arm64.deb
            return 1
        fi
        apt install ./linux-headers-6.4.0+-arm64.deb ./linux-image-6.4.0+-arm64.deb ./linux-libc-dev_-6.4.0-arm64.deb
        # Clean up
        rm linux-headers-6.4.0+-arm64.deb linux-image-6.4.0+-arm64.deb linux-libc-dev_-6.4.0-arm64.deb
    else
        echo "$(uname -m) is not supported"
    fi
    return 0
}
