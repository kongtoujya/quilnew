#!/bin/bash

# Step 0: Welcome
echo "✨ Welcome! This script will update your Quilibrium node when running it as a service. ✨"
echo ""
echo "Made with 🔥 by LaMat - https://quilibrium.one"
echo "====================================================================================="
echo ""
echo "Processing... ⏳"
sleep 7  # Add a 7-second delay

#===========================
# Set variables
#===========================
# Set sCPU limit
CPU_LIMIT_PERCENT=70
# Set service file path
SERVICE_FILE="/lib/systemd/system/ceremonyclient.service"
# User working folder
HOME=$(eval echo ~$USER)
# Node path
NODE_PATH="$HOME/ceremonyclient/node"

#===========================
# Check if ceremonyclient directory exists
#===========================
HOME=$(eval echo ~$USER)
CEREMONYCLIENT_DIR="$HOME/ceremonyclient"

if [ ! -d "$CEREMONYCLIENT_DIR" ]; then
    echo "❌ Error: You don't have a node installed yet. Nothing to update. Exiting..."
    exit 1
fi

#===========================
# CPU limit cheks
#===========================
# Calculate the number of vCores
vCORES=$(nproc)
# Calculate the CPUQuota value
CPU_QUOTA=$(($CPU_LIMIT_PERCENT * $vCORES))

# Remove existing CPUQuota line from the service file
if sudo sed -i "/CPUQuota=/d" "$SERVICE_FILE"; then
    echo "➖ Removed existing CPUQuota from service file."
else
    echo "ℹ️ No existing CPUQuota found in service file."
fi

# Add the new CPUQuota line
if ! sudo sed -i "/\[Service\]/a CPUQuota=${CPU_QUOTA}%" "$SERVICE_FILE"; then
    echo "❌ Error: Failed to add CPUQuota to ceremonyclient service file." >&2
    exit 1
else
    echo "➕ Added CPUQuota=${CPU_QUOTA}% to service file."
    echo " This will limit your CPU by $CPU_LIMIT_PERCENT %"
fi
sleep 1
#===========================
# Stop the ceremonyclient service if it exists
#===========================
echo "⏳ Stopping the ceremonyclient service if it exists..."
if systemctl is-active --quiet ceremonyclient; then
    if sudo systemctl stop ceremonyclient; then
        echo "🔴 Service stop command issued."
    else
        echo "❌ Failed to issue stop command for ceremonyclient service." >&2
    fi

    sleep 1

    # Verify the service has stopped
    if systemctl is-active --quiet ceremonyclient; then
        echo "⚠️ Service is still running. Attempting to stop it forcefully..."
        if sudo systemctl kill ceremonyclient; then
            sleep 1
            if systemctl is-active --quiet ceremonyclient; then
                echo "❌ Service could not be stopped forcefully." >&2
            else
                echo "✅ Service stopped forcefully."
            fi
        else
            echo "❌ Failed to force stop the ceremonyclient service." >&2
        fi
    else
        echo "✅ Service stopped successfully."
    fi
else
    echo "ℹ️ Ceremonyclient service is not running or does not exist."
fi

sleep 1

#===========================
# Move to the ceremonyclient directory
#===========================
echo "Moving to the ceremonyclient directory..."
cd ~/ceremonyclient || { echo "❌ Error: Directory ~/ceremonyclient does not exist."; exit 1; }

#===========================
# Discard local changes in release_autorun.sh
#===========================
echo "✅ Discarding local changes in release_autorun.sh..."
git checkout -- node/release_autorun.sh

#===========================
# Download Binary
#===========================
echo "⏳ Downloading New Release..."

# Change to the ceremonyclient directory
cd ~/ceremonyclient || { echo "❌ Error: Directory ~/ceremonyclient does not exist."; exit 1; }

# Set the remote URL and verify access
for url in \
    "https://source.quilibrium.com/quilibrium/ceremonyclient.git" \
    "https://git.quilibrium-mirror.ch/agostbiro/ceremonyclient.git" \
    "https://github.com/QuilibriumNetwork/ceremonyclient.git"; do
    if git remote set-url origin "$url" && git fetch origin; then
        echo "✅ Remote URL set to $url"
        break
    fi
done

# Check if the URL was set and accessible
if ! git remote -v | grep -q origin; then
    echo "❌ Error: Failed to set and access remote URL." >&2
    exit 1
fi

# Pull the latest changes
git pull || { echo "❌ Error: Failed to download the latest changes." >&2; exit 1; }
git checkout release || { echo "❌ Error: Failed to checkout release." >&2; exit 1; }

echo "✅ Downloaded the latest changes successfully."

sleep 1
#===========================
# Determine the ExecStart line based on the architecture
#===========================
# Set the version number
VERSION=$(cat $NODE_PATH/config/version.go | grep -A 1 "func GetVersion() \[\]byte {" | grep -Eo '0x[0-9a-fA-F]+' | xargs printf "%d.%d.%d")

# Get the system architecture
ARCH=$(uname -m)

if [ "$ARCH" = "x86_64" ]; then
    EXEC_START="$NODE_PATH/node-$VERSION-linux-amd64"
elif [ "$ARCH" = "aarch64" ]; then
    EXEC_START="$NODE_PATH/node-$VERSION-linux-arm64"
elif [ "$ARCH" = "arm64" ]; then
    EXEC_START="$NODE_PATH/node-$VERSION-darwin-arm64"
else
    echo "❌ Unsupported architecture: $ARCH"
    exit 1
fi

sleep 1
#===========================
# Re-Create or Update Ceremonyclient Service
#===========================
echo "🔧 Rebuilding Ceremonyclient Service..."
sleep 2  # Add a 2-second delay
if [ ! -f "$SERVICE_FILE" ]; then
    echo "📝 Creating new ceremonyclient service file..."
    if ! sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Ceremony Client Go App Service

[Service]
Type=simple
Restart=always
RestartSec=5s
WorkingDirectory="$NODE_PATH"
ExecStart="$EXEC_START"

[Install]
WantedBy=multi-user.target
EOF
    then
        echo "❌ Error: Failed to create ceremonyclient service file." >&2
        exit 1
    fi
else
    echo "🔍 Checking existing ceremonyclient service file..."

    # Check if the required lines exist or are different
    if ! grep -q "WorkingDirectory=$NODE_PATH" "$SERVICE_FILE" || ! grep -q "ExecStart=$EXEC_START" "$SERVICE_FILE"; then
        echo "🔄 Updating existing ceremonyclient service file..."
        # Replace the existing lines with new values
        if ! sudo sed -i "s|WorkingDirectory=.*|WorkingDirectory=$NODE_PATH|" "$SERVICE_FILE"; then
            echo "❌ Error: Failed to update WorkingDirectory in ceremonyclient service file." >&2
            exit 1
        fi
        if ! sudo sed -i "s|ExecStart=.*|ExecStart=$EXEC_START|" "$SERVICE_FILE"; then
            echo "❌ Error: Failed to update ExecStart in ceremonyclient service file." >&2
            exit 1
        fi
    else
        echo "✅ No changes needed."
    fi
fi  
sleep 1  # Add a 1-second delay

#===========================
# Remove the SELF_TEST file
#===========================
if [ -f "$NODE_PATH/.config/SELF_TEST" ]; then
    echo "🗑️ Removing SELF_TEST file..."
    if rm "$NODE_PATH/.config/SELF_TEST"; then
        echo "✅ SELF_TEST file removed successfully."
    else
        echo "❌ Error: Failed to remove SELF_TEST file." >&2
        exit 1
    fi
else
    echo "ℹ️ No SELF_TEST file found at $NODE_PATH/.config/SELF_TEST."
fi
sleep 1  # Add a 1-second delay

#===========================
# Start the ceremonyclient service
#===========================
echo "✅ Starting Ceremonyclient Service"
sleep 2  # Add a 2-second delay
systemctl daemon-reload
systemctl enable ceremonyclient
service ceremonyclient start

#===========================
# Showing the node logs
#===========================
echo ""
echo "🌟Your Qnode is now updated to $VERSION!"
echo ""
echo "⏳ Showing the node log... (Hit Ctrl+C to exit log)"
sleep 1
sudo journalctl -u ceremonyclient.service -f --no-hostname -o cat
