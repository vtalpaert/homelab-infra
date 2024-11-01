#!/bin/bash

# Set variables
SNAP=microk8s
VERSION=1.31

while getopts ":v:" option; do
    case $option in
    v) # Enter a name
        VERSION=$OPTARG ;;
    \?) # Invalid option
        echo "Error: Invalid option"
        exit
        ;;
    esac
done

# Install basics
sudo apt update
sudo apt install -y git

# Install or refresh snap
if [[ "$(snap info $SNAP | grep -c 'installed: ')" -eq 1 ]]; then
    echo Refeshing $SNAP
    sudo snap refresh $SNAP --classic --channel=$VERSION
else
    echo Installing $SNAP
    sudo snap install $SNAP --classic --channel=$VERSION
fi

# Add to group
GROUP=$SNAP
if id -nG "$USER" | grep -qw "$GROUP"; then
    echo $USER already belongs to $GROUP
else
    echo adding $USER to group $GROUP
    sudo usermod -a -G $GROUP $USER
    newgrp $GROUP
fi

microk8s status --wait-ready
microk8s enable ingress
microk8s enable cert-manager
microk8s enable metallb 192.168.144.0/20
