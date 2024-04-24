#!/bin/bash

# Pause the script for 60 seconds to ensure all system services have started properly.
sleep 60s

# Navigate to the home directory.
cd $HOME

# This script installs the BBRx congestion control algorithm. It is adapted from https://github.com/KozakaiAya/TCP_BBR.

# Check and install dkms if it is not already installed.
if [ ! -x /usr/sbin/dkms ]; then
    apt-get -y install dkms
    if [ ! -x /usr/sbin/dkms ]; then
        echo "Error: DKMS installation failed." >&2
        exit 1
    fi
fi

# Ensure the necessary kernel headers are present.
if [ ! -f /usr/src/linux-headers-$(uname -r)/.config ]; then
    if [[ -z $(apt-cache search linux-headers-$(uname -r)) ]]; then
        echo "Error: Kernel headers for $(uname -r) are not available." >&2
        exit 1
    fi
    apt-get -y install linux-headers-$(uname -r)
    if [ ! -f /usr/src/linux-headers-$(uname -r)/.config ]; then
        echo "Error: Installation of kernel headers for $(uname -r) failed." >&2
        exit 1
    fi
fi

# Download the BBRx source code.
curl -O "https://raw.githubusercontent.com/iamnhx/seedbox/main/BBR/BBRx/tcp_bbrx.c"
if [ ! -f $HOME/tcp_bbrx.c ]; then
    echo "Error: Failed to download the BBRx source code." >&2
    exit 1
fi

# Define kernel version and algorithm.
kernel_ver="5.15.0"
algo="bbrx"

# Prepare for compilation.
bbr_file="tcp_$algo"
bbr_src="$bbr_file.c"
bbr_obj="$bbr_file.o"

# Create necessary directories and move source files.
mkdir -p $HOME/.bbr/src
mv $HOME/$bbr_src $HOME/.bbr/src/$bbr_src

# Generate the Makefile for building the module.
cat > $HOME/.bbr/src/Makefile << EOF
obj-m := $bbr_obj

default:
	make -C /lib/modules/\$(shell uname -r)/build M=\$(PWD) modules

clean:
	-rm modules.order
	-rm Module.symvers
	-rm -f .[!.]* ..?* *.o *.ko *.mod.* *.symvers
EOF

# Configure DKMS.
cat > $HOME/.bbr/dkms.conf << EOF
MAKE="'make' -C src/"
CLEAN="'make' -C src/ clean"
BUILT_MODULE_NAME=$bbr_file
BUILT_MODULE_LOCATION="src/"
DEST_MODULE_LOCATION="/updates/net/ipv4"
PACKAGE_NAME="$algo"
PACKAGE_VERSION="$kernel_ver"
REMAKE_INITRD="yes"
EOF

# Install the module via DKMS.
cp -R $HOME/.bbr /usr/src/$algo-$kernel_ver
dkms add -m $algo -v $kernel_ver
dkms build -m $algo -v $kernel_ver
dkms install -m $algo -v $kernel_ver

# Check for DKMS errors.
if [ $? -ne 0 ]; then
    dkms remove -m $algo/$kernel_ver --all
    echo "Error: DKMS installation failed." >&2
    exit 1
fi

# Load the module and configure system settings for automatic loading at boot.
modprobe $bbr_file
if [ $? -ne 0 ]; then
    echo "Error: Module loading failed." >&2
    exit 1
fi

# Configure the system to use the new TCP congestion control module at startup.
echo $bbr_file | sudo tee -a /etc/modules
sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = $algo" >> /etc/sysctl.conf
sysctl -p > /dev/null

# Cleanup installation residue.
rm -r $HOME/.bbr
systemctl disable bbrinstall.service
rm /etc/systemd/system/bbrinstall.service
rm /opt/seedbox/BBRx.sh
