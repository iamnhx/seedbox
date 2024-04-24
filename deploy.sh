#!/bin/sh
tput sgr0; clear
mkdir -p /opt/seedbox 

## Load Seedbox Modules
source <(curl -s https://raw.githubusercontent.com/iamnhx/seedbox/main/seedbox_installation.sh)
# Verify if the Seedbox modules are successfully loaded.
if [ $? -ne 0 ]; then
    echo "Failed to load Seedbox modules."
    echo "Please verify the connection with GitHub."
    exit 1
fi

## Load loading animation
source <(curl -s https://raw.githubusercontent.com/Silejonu/bash_loading_animations/main/bash_loading_animations.sh)
# Verify if the Bash loading animation is successfully loaded.
if [ $? -ne 0 ]; then
    printErrorMessage "Failed to load Bash loading animation."
    printErrorAndExit "Please verify the connection with GitHub."
fi
# Run BLA::stop_loading_animation if the script is interrupted.
trap BLA::stop_loading_animation SIGINT

## Install function
install_() {
    printIndentedInfoMessage "$2"
    BLA::start_loading_animation "${BLA_classic[@]}"  # Start animation

    # Execute the command and redirect both stdout and stderr to the log file
    $1 > $3 2>&1
    local status=$?  # Capture the exit status of the command

    if [ $status -ne 0 ]; then
        printOverwriteErrorMessage "    Failed to install. See $3 for details."
    else
        printOverwriteInfoMessage "    ✓ Done."
        export $4=1  # Set environment variable to indicate success
    fi
	BLA::stop_loading_animation  # Stop animation
}

## Sanitizing log files
sanitize_logs() {
    # Find all _log files in the /tmp directory and clean them using sed
    find /tmp -type f -name '*_log' -exec sed -i -E 's/\x1b(\[[0-9;?]*[mHKJ]|[()#%][0-9]?[ABCDHIJKSTZfnqrstuxy=]|[()][NnO]|[()#%][<>]|[()= \-\.][0-9]+)|\x1b[\]\^[PX^_].|\x1b[\]7]//g' {} \;
}

## Checking Prerequisites
printInfoMessage "Checking & installing prerequisites..."
# Check root privilege.
if [ $(id -u) -ne 0 ]; then 
    printErrorAndExit "This script requires root permissions to run."
fi

# Linux Distro Version check
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
    OS=Debian
    VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSe-release ]; then
    OS=SuSe
elif [ -f /etc/redhat-release ]; then
    OS=Redhat
else
    OS=$(uname -s)
    VER=$(uname -r)
fi

if [[ ! "$OS" =~ "Debian" ]] && [[ ! "$OS" =~ "Ubuntu" ]]; then  # Only Debian and Ubuntu are supported.
    printErrorMessage "Unsupported OS: $OS $VER."
    printInfoMessage "This script supports only Debian 10+ and Ubuntu 20.04+."
    exit 1
fi

if [[ "$OS" =~ "Debian" ]]; then  # Debian 10+ are supported.
    if [[ ! "$VER" =~ "10" ]] && [[ ! "$VER" =~ "11" ]] && [[ ! "$VER" =~ "12" ]]; then
        printErrorMessage "Unsupported Debian version: $OS $VER."
        printInfoMessage "Only Debian 10+ is supported."
        exit 1
    fi
fi

if [[ "$OS" =~ "Ubuntu" ]]; then  # Ubuntu 20.04+ are supported.
    if [[ ! "$VER" =~ "20" ]] && [[ ! "$VER" =~ "22" ]] && [[ ! "$VER" =~ "23" ]]; then
        printErrorMessage "Unsupported Ubuntu version: $OS $VER."
        printInfoMessage "Only Ubuntu 20.04+ is supported."
        exit 1
    fi
fi

## Read input arguments
while getopts "u:p:c:q:l:rbvx3oh" opt; do
    case ${opt} in
        u ) # Process the username option.
            username=${OPTARG}
            ;;
        p ) # Process the password option.
            password=${OPTARG}
            ;;
        c ) # Process the cache option.
            cache=${OPTARG}
            # Check if cache is a number.
            while true
            do
                if ! [[ "$cache" =~ ^[0-9]+$ ]]; then
                    printWarningMessage "Cache size must be a number."
                    printInputPrompt "Please enter the cache size (in MiB):"
                    read cache
                else
                    break
                fi
            done
            # Converting the cache to qBittorrent's unit (MiB).
            qb_cache=$cache
            ;;
        q ) # Process option cache.
            qb_install=1
            qb_ver=("qBittorrent-${OPTARG}")
            ;;
        l ) # Process option libtorrent.
            lib_ver=("libtorrent-${OPTARG}")
            # Check if a qBittorrent version is specified.
            if [ -z "$qb_ver" ]; then
                printWarningMessage "You must select a qBittorrent version for your libtorrent install."
                qb_ver_select
            fi
            ;;
        r ) # Process option autoremove.
            autoremove_install=1
            ;;
        b ) # Process option autobrr.
            autobrr_install=1
            ;;
        v ) # Process option vertex.
            vertex_install=1
            ;;
        x ) # Process option BBRx.
            unset bbrv3_install
            bbrx_install=1      
            ;;
        3 ) # Process option BBR.
            unset bbrx_install
            bbrv3_install=1
            ;;
        o ) # Process option port.
            if [[ -n "$qb_install" ]]; then
                printInputPrompt "Please enter the qBittorrent port:"
                read qb_port
                while true
                do
                    if ! [[ "$qb_port" =~ ^[0-9]+$ ]]; then
                        printWarningMessage "Port must be a number."
                        printInputPrompt "Please enter the qBittorrent port:"
                        read qb_port
                    else
                        break
                    fi
                done
                printInputPrompt "Please enter the qBittorrent incoming port:"
                read qb_incoming_port
                while true
                do
                    if ! [[ "$qb_incoming_port" =~ ^[0-9]+$ ]]; then
                        printWarningMessage "Port must be a number."
                        printInputPrompt "Please enter the qBittorrent incoming port:"
                        read qb_incoming_port
                    else
                        break
                    fi
                done
            fi
            if [[ -n "$autobrr_install" ]]; then
                printInputPrompt "Please enter the autobrr port:"
                read autobrr_port
                while true
                do
                    if ! [[ "$autobrr_port" =~ ^[0-9]+$ ]]; then
                        printWarningMessage "Port must be a number."
                        printInputPrompt "Please enter the autobrr port:"
                        read autobrr_port
                    else
                        break
                    fi
                done
            fi
            if [[ -n "$vertex_install" ]]; then
                printInputPrompt "Please enter the vertex port:"
                read vertex_port
                while true
                do
                    if ! [[ "$vertex_port" =~ ^[0-9]+$ ]]; then
                        printWarningMessage "Port must be a number."
                        printInputPrompt "Please enter the vertex port:"
                        read vertex_port
                    else
                        break
                    fi
                done
            fi
            ;;
        h ) # Process option help.
            printInfoMessage "Help:"
            printInfoMessage "Usage: ./Install.sh -u <username> -p <password> -c <Cache Size (unit: MiB)> -q <qBittorrent version> -l <libtorrent version> -b -v -r -x -o"
            printInfoMessage "Example: ./Install.sh -u user -p password -c 3072 -q 4.3.9 -l v1.2.19 -b -v -r -x -o"
            source <(curl -s https://raw.githubusercontent.com/iamnhx/seedbox/main/qBittorrent/qBittorrent_install.sh)
            separator
            printInfoMessage "Options:"
            printInputPrompt "1. -u : Username"
            printInputPrompt "2. -p : Password"
            printInputPrompt "3. -c : Cache Size for qBittorrent (unit: MiB)"
            echo -e "\n"
            printInputPrompt "4. -q : qBittorrent version"
            printInputPrompt "Available qBittorrent versions:"
            tput sgr0; tput setaf 7; tput dim; history -p "${qb_ver_list[@]}"; tput sgr0
            echo -e "\n"
            printInputPrompt "5. -l : libtorrent version"
            printInputPrompt "Available libtorrent versions:"
            tput sgr0; tput setaf 7; tput dim; history -p "${lib_ver_list[@]}"; tput sgr0
            echo -e "\n"
            printInputPrompt "6. -r : Install autoremove-torrents"
            printInputPrompt "7. -b : Install autobrr"
            printInputPrompt "8. -v : Install vertex"
            printInputPrompt "9. -x : Install BBRx"
            printInputPrompt "10. -3 : Install BBRv3"
            printInputPrompt "11. -o : Specify ports for qBittorrent, autobrr, and vertex"
            printInputPrompt "12. -h : Display help message"
            exit 0
            ;;
        \? ) 
            printInfoMessage "Help:"
            printIndentedInfoMessage "Usage: ./deploy.sh -u <username> -p <password> -c <Cache Size (unit: MiB)> -q <qBittorrent version> -l <libtorrent version> -b -v -r -3 -x -o"
            printIndentedInfoMessage "Example: ./deploy.sh -u <username> -p <password> -c 3072 -q 4.3.9 -l v1.2.19 -b -v -r -3 -x"
            exit 1
            ;;
    esac
done

# System Update & Dependencies Install
update_and_install_dependencies

## Deploying Seedbox
tput sgr0; clear
printInfoMessage "Deploying Seedbox"
echo -e "\n"

# qBittorrent
source <(curl -s https://raw.githubusercontent.com/iamnhx/seedbox/main/qBittorrent/qBittorrent_install.sh)
# Check if the qBittorrent install is successfully loaded.
if [ $? -ne 0 ]; then
    printErrorAndExit "qBittorrent install failed to load."
fi

if [[ ! -z "$qb_install" ]]; then
    ## Check if all the required arguments are specified.
    # Check if username is specified.
    if [ -z "$username" ]; then
        printWarningMessage "Username is not specified."
        printInputPrompt "Please enter a username:"
        read username
    fi
    # Check if password is specified.
	if [ -z "$password" ]; then
        printWarningMessage "Password is not specified."
        printInputPrompt "Please enter a password:"
        read password
    fi
    ## Create user if it does not exist.
    if ! id -u $username > /dev/null 2>&1; then
        useradd -m -s /bin/bash $username
        # Check if the user is created successfully.
        if [ $? -ne 0 ]; then
            printWarningMessage "Failed to create user $username."
            return 1
        fi
    fi
    chown -R $username:$username /home/$username
    # Check if cache is specified.
    if [ -z "$cache" ]; then
        printWarningMessage "Cache is not specified."
        printInputPrompt "Please enter a cache size (in MiB):"
        read cache
        # Check if cache is a number.
        while true
        do
            if ! [[ "$cache" =~ ^[0-9]+$ ]]; then
                printWarningMessage "Cache must be a number."
                printInputPrompt "Please enter a cache size (in MiB):"
                read cache
            else
                break
            fi
        done
        qb_cache=$cache
    fi
    # Check if qBittorrent version is specified.
    if [ -z "$qb_ver" ]; then
        printWarningMessage "qBittorrent version is not specified."
        qb_ver_check
    fi
    # Check if libtorrent version is specified.
    if [ -z "$lib_ver" ]; then
        printWarningMessage "libtorrent version is not specified."
        lib_ver_check
    fi
    # Check if qBittorrent port is specified.
    if [ -z "$qb_port" ]; then
        qb_port=9000
    fi
    # Check if qBittorrent incoming port is specified.
    if [ -z "$qb_incoming_port" ]; then
        qb_incoming_port=45000
    fi

    ## qBittorrent & libtorrent compatibility check.
    qb_install_check

    ## qBittorrent install.
    install_ "install_qBittorrent_ $username $password $qb_ver $lib_ver $qb_cache $qb_port $qb_incoming_port" "Installing qBittorrent" "/tmp/qb_log" qb_install_success
fi

# autobrr Install
if [[ ! -z "$autobrr_install" ]]; then
    install_ install_autobrr_ "Installing autobrr" "/tmp/autobrr_log" autobrr_install_success
fi

# vertex Install
if [[ ! -z "$vertex_install" ]]; then
    install_ install_vertex_ "Installing vertex" "/tmp/vertex_log" vertex_install_success
fi

# autoremove-torrents Install
if [[ ! -z "$autoremove_install" ]]; then
    install_ install_autoremove-torrents_ "Installing autoremove-torrents" "/tmp/autoremove_log" autoremove_install_success
fi

separator

## System Tuning
printInfoMessage "System Optimization & Tuning"

# Check if a virtual environment is in use, since specific configurations might not work properly on a virtual machine.
systemd-detect-virt > /dev/null
if [ $? -eq 0 ]; then
    printWarningMessage "Virtualization detected; some tuning will be omitted."
    install_ disable_tso_ "Disabling TSO" "/tmp/tso_log" tso_success
else
    install_ set_disk_scheduler_ "Setting Disk Scheduler" "/tmp/disk_scheduler_log" disk_scheduler_success
    install_ set_ring_buffer_ "Setting Ring Buffer" "/tmp/ring_buffer_log" ring_buffer_success
fi

install_ tuned_ "Installing tuned" "/tmp/tuned_log" tuned_success
install_ set_txqueuelen_ "Setting txqueuelen" "/tmp/txqueuelen_log" txqueuelen_success
install_ set_file_open_limit_ "Setting File Open Limit" "/tmp/file_open_limit_log" file_open_limit_success

install_ set_initial_congestion_window_ "Setting Initial Congestion Window" "/tmp/initial_congestion_window_log" initial_congestion_window_success
install_ kernel_settings_ "Setting Kernel Settings" "/tmp/kernel_settings_log" kernel_settings_success

# BBRx
if [[ ! -z "$bbrx_install" ]]; then
    # Check if Tweaked BBR is already installed.
    if [[ ! -z "$(lsmod | grep bbrx)" ]]; then
        printWarningMessage "Tweaked BBR is already installed."
    else
        install_ install_bbrx_ "Installing BBRx" "/tmp/bbrx_log" bbrx_install_success
    fi
fi

# BBRv3
if [[ ! -z "$bbrv3_install" ]]; then
    install_ install_bbrv3_ "Installing BBRv3" "/tmp/bbrv3_log" bbrv3_install_success
fi

separator

## Configure Boot Script
printWarningMessage "Configuring Boot Script..."
touch /opt/seedbox/.boot-script.sh && chmod +x /opt/seedbox/.boot-script.sh
cat << EOF > /opt/seedbox/.boot-script.sh
#!/bin/bash
sleep 120s
source <(curl -s https://raw.githubusercontent.com/iamnhx/seedbox/main/seedbox_installation.sh)
# Check if the Seedbox Modules are successfully loaded.
if [ \$? -ne 0 ]; then
    exit 1
fi
set_txqueuelen_
# Check for Virtual Environment since some of the tuning might not work on a virtual machine.
systemd-detect-virt > /dev/null
if [ \$? -eq 0 ]; then
    disable_tso_
else
    set_disk_scheduler_
    set_ring_buffer_
fi
set_initial_congestion_window_
EOF
# Configure the script to run during system startup.
cat << EOF > /etc/systemd/system/boot-script.service
[Unit]
Description=boot-script
After=network.target

[Service]
Type=simple
ExecStart=/opt/seedbox/.boot-script.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable boot-script.service

separator

## Deploying qBittorrent Controller
printInfoMessage "Configuring qBittorrent Controller..."

# Set timezone to match localtime (ensure tzdata is installed)
ln -fs /usr/share/zoneinfo/$(cat /etc/timezone) /etc/localtime
dpkg-reconfigure --frontend noninteractive tzdata > /dev/null 2>&1

# Download the qb_controller.py script
curl -s https://raw.githubusercontent.com/iamnhx/seedbox/main/qBittorrent/qb_controller.py -o /opt/seedbox/qb_controller.py

# Create a systemd service to run the script at boot
cat > /etc/systemd/system/qb_controller.service <<EOF
[Unit]
Description=qBittorrent Controller
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/seedbox/qb_controller.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl enable qb_controller.service
systemctl start qb_controller.service

separator

## Finalizing the install
printInfoMessage "Seedbox Installation Complete"
publicip=$(curl -s https://ipinfo.io/ip)

sanitize_logs

# Display Username and Password
# qBittorrent
if [[ ! -z "$qb_install_success" ]]; then
    printInfoMessage "[qBittorrent]"
    printDimMessage "qBittorrent WebUI: http://$publicip:$qb_port"
    printDimMessage "qBittorrent Username: $username"
    printDimMessage "qBittorrent Password: $password"
    echo -e "\n"
fi
# autoremove-torrents
if [[ ! -z "$autoremove_install_success" ]]; then
    printInfoMessage "[autoremove-torrents]"
    printDimMessage "Config at /home/$username/.config.yml"
    printDimMessage "Please read https://autoremove-torrents.readthedocs.io/en/latest/config.html for configuration."
    echo -e "\n"
fi
# autobrr
if [[ ! -z "$autobrr_install_success" ]]; then
    printInfoMessage "[autobrr]"
    printDimMessage "autobrr WebUI: http://$publicip:$autobrr_port"
    echo -e "\n"
fi
# vertex
if [[ ! -z "$vertex_install_success" ]]; then
    printInfoMessage "[vertex]"
    printDimMessage "vertex WebUI: http://$publicip:$vertex_port"
    printDimMessage "vertex Username: $username"
    printDimMessage "vertex Password: $password"
    echo -e "\n"
fi
# BBR
if [[ ! -z "$bbrx_install_success" ]]; then
    printInfoMessage "BBRx has been successfully installed. A system reboot is required for the modifications to take effect."
fi

if [[ ! -z "$bbrv3_install_success" ]]; then
    printInfoMessage "BBRv3 has been successfully installed. A system reboot is required for the modifications to take effect."
fi

exit 0
