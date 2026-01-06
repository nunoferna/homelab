#!/bin/bash
set -e

echo "--- [K3s] Installing K3s Distribution ---"

if grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null || [ -f /etc/rpi-issue ]; then
    echo "--- [RPi] Checking Cgroups ---"
    CMDLINE_PATH="/boot/firmware/cmdline.txt"
    if [ ! -f "$CMDLINE_PATH" ]; then
        # Older Raspbian
        CMDLINE_PATH="/boot/cmdline.txt"
    fi

    if [ -f "$CMDLINE_PATH" ]; then
        if ! grep -q "cgroup_memory=1 cgroup_enable=memory" "$CMDLINE_PATH"; then
            echo "--- [RPi] Enabling Cgroups in $CMDLINE_PATH ---"
            echo "Appending 'cgroup_memory=1 cgroup_enable=memory' to $CMDLINE_PATH"
            sudo cp "$CMDLINE_PATH" "$CMDLINE_PATH.bak"
            sudo sed -i 's/$/ cgroup_memory=1 cgroup_enable=memory/' "$CMDLINE_PATH"
            
            echo "!!! REBOOT REQUIRED !!!"
            echo "Cgroups enabled. You MUST reboot your Raspberry Pi for this to take effect."
            echo "After reboot, run this script again."
            exit 1
        else
             echo "--- [RPi] Cgroups already enabled. ---"
        fi
    else
        echo "WARNING: Could not find cmdline.txt to enable cgroups. If K3s fails, check docs."
    fi
    
    # Check for legacy iptables (Debian/RPi issue)
    if ! command -v iptables-save &> /dev/null; then
         echo "--- [RPi] Installing iptables ---"
         sudo apt-get install -y iptables
    fi
fi


if ! command -v k3s &> /dev/null; then
    # Create K3s config directory
    sudo mkdir -p /etc/rancher/k3s
    
    # Locate configuration relative to this script
    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
    CONFIG_SRC="$SCRIPT_DIR/config.yaml"

    if [ -f "$CONFIG_SRC" ]; then
        sudo cp "$CONFIG_SRC" /etc/rancher/k3s/config.yaml
        echo "K3s configuration file installed from $CONFIG_SRC"
    else
        echo "WARNING: config.yaml not found at $CONFIG_SRC. Falling back to default install."
    fi

    echo "Installing K3s..."
    curl -sfL https://get.k3s.io | sh -
    echo "K3s installed."
else
    echo "K3s is already installed."
fi

echo "--- [K3s] Configuring User Access ---"
if [ -f /etc/rancher/k3s/k3s.yaml ]; then
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    REAL_USER=${SUDO_USER:-$USER}
    sudo chown $REAL_USER:$(id -gn $REAL_USER) ~/.kube/config
    chmod 600 ~/.kube/config
    echo "Kubeconfig copied to ~/.kube/config for user $REAL_USER"
fi
