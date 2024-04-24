# Seedbox Deployment Script

## Overview

This script automates the deployment of a seedbox on Debian or Ubuntu systems. It handles the installation of qBittorrent, autobrr, vertex, and autoremove-torrents, and applies network and system optimizations to boost performance.

## Prerequisites

- Root access.
- Debian 10+ or Ubuntu 20.04+.

## Usage

Execute the script with required parameters:

```bash
bash <(curl -s https://raw.githubusercontent.com/iamnhx/seedbox/main/deploy.sh) -u [username] -p [password] -c [cache size] -q [qBittorrent version] -l [libtorrent version] -b -v -r -x -o
```

## Parameters

    -u: Username
    -p: Password
    -c: Cache size for qBittorrent (MiB)
    -q: qBittorrent version
    -l: libtorrent version
    -b: Install autobrr
    -v: Install vertex
    -r: Install autoremove-torrents
    -x: Install BBRx
    -3: Install BBRv3
    -o: Custom port settings

## Guidelines

Allocate approximately one-quarter of the total available RAM of the machine for the cache size. If using qBittorrent version 4.3.x, consider potential memory leakage issues and limit the cache to one-eighth of the available RAM.