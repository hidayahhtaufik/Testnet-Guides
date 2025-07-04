#!/bin/bash

# Check if running as root, if not re-execute with sudo
if [ "$(id -u)" -ne 0 ]; then
    exec sudo bash "$0" "$@"
    exit $?
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
PEER_ITROCKET="01f8a2148a94f0267af919d2eab78452c90d9864@story-testnet-peer.itrocket.net:52656"
PEER_AURANODE="95a5d069b6b7778ccde6b8dc0ed7727cf9823729@story-aeneid-p2p.auranode.xyz:26656"
SNAPSHOT_ITROCKET_STORY="https://server-3.itrocket.net/testnet/story/story_2025-07-04_6274836_snap.tar.lz4"
SNAPSHOT_ITROCKET_GETH="https://server-3.itrocket.net/testnet/story/geth_story_2025-07-04_6274836_snap.tar.lz4"
SNAPSHOT_AURANODE_STORY="https://story-aeneid-snapshot.auranode.xyz/Story_snapshot.tar.lz4"
SNAPSHOT_AURANODE_GETH="https://story-geth-aeneid-snapshot.auranode.xyz/Geth_snapshot.tar.lz4"
RPC_ITROCKET="https://story-testnet-rpc.itrocket.net:443"
RPC_AURANODE="https://story-aeneid-rpc.auranode.xyz"

# Check root
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}This script must be run as root!${NC}"
  exit 1
fi

# Main menu
show_menu() {
  clear
  echo -e "${YELLOW}======================================${NC}"
  echo -e "${YELLOW}   Story Aeneid Validator Installer   ${NC}"
  echo -e "${YELLOW}======================================${NC}"
  echo -e "1.  Auto Install Validator"
  echo -e "2.  Apply Snapshot"
  echo -e "3.  Upgrade Binary"
  echo -e "4.  State Sync Configuration"
  echo -e "5.  Node Sync Status"
  echo -e "6.  Manage Peers"
  echo -e "7.  Delete Node"
  echo -e "8.  Exit"
  echo -e "${YELLOW}======================================${NC}"
  read -p "Choose an option: " choice
}

# Auto install
auto_install() {
  echo -e "${GREEN}>>> Starting auto-installation...${NC}"
  
  # Install dependencies
  echo -e "${CYAN}Installing dependencies...${NC}"
  sudo apt update -y
  sudo apt-get update -y
  sudo apt install curl git make jq build-essential gcc unzip wget pv lz4 aria2 tmux -y

  # Install GO
  if ! command -v go &> /dev/null; then
    echo -e "${CYAN}Installing Go...${NC}"
    cd $HOME
    ver="1.22.0"
    wget "https://golang.org/dl/go$ver.linux-amd64.tar.gz"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "go$ver.linux-amd64.tar.gz"
    rm "go$ver.linux-amd64.tar.gz"
    echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> ~/.bash_profile
    source ~/.bash_profile
    go version
  else
    echo -e "${YELLOW}Go already installed. Skipping...${NC}"
  fi

  # Install story-geth
  echo -e "${CYAN}Installing story-geth v1.1.0...${NC}"
  cd $HOME
  git clone https://github.com/piplabs/story-geth
  cd story-geth
  git checkout v1.1.0
  make geth
  cp build/bin/geth $HOME/go/bin/story-geth
  source $HOME/.bash_profile
  story-geth version

  # Install story
  echo -e "${CYAN}Installing story v1.3.0...${NC}"
  cd $HOME
  rm -rf story-linux-amd64
  wget https://github.com/piplabs/story/releases/download/v1.3.0/story-linux-amd64
  [ ! -d "$HOME/go/bin" ] && mkdir -p $HOME/go/bin
  if ! grep -q "$HOME/go/bin" $HOME/.bash_profile; then
    echo "export PATH=$PATH:/usr/local/go/bin:~/go/bin" >> ~/.bash_profile
  fi
  chmod +x story-linux-amd64
  sudo cp $HOME/story-linux-amd64 $HOME/go/bin/story
  source $HOME/.bash_profile
  story version

  # Initialize node
  read -p "Enter your moniker name: " MONIKER
  story init --network aeneid --moniker "$MONIKER"

  # Create services
  create_services

  # Apply snapshot
  apply_snapshot_menu
}

# Create systemd services
create_services() {
  # Story-geth service
  sudo tee /etc/systemd/system/story-geth.service > /dev/null <<EOF
[Unit]
Description=Story Geth Client
After=network.target

[Service]
User=root
ExecStart=/root/go/bin/story-geth --aeneid --syncmode full
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

  # Story service
  sudo tee /etc/systemd/system/story.service > /dev/null <<EOF
[Unit]
Description=Story Consensus Client
After=network.target

[Service]
User=root
ExecStart=/root/go/bin/story run
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

  # Reload systemd
  sudo systemctl daemon-reload
  echo -e "${GREEN}Systemd services created!${NC}"
}

# Snapshot menu
snapshot_menu() {
  clear
  echo -e "${YELLOW}=======================${NC}"
  echo -e "${YELLOW}    SNAPSHOT SOURCE    ${NC}"
  echo -e "${YELLOW}=======================${NC}"
  echo -e "1. ITRocket"
  echo -e "2. Auranode"
  echo -e "3. Back to main menu"
  read -p "Choose snapshot source: " choice
  
  case $choice in
    1) apply_snapshot "itrocket";;
    2) apply_snapshot "auranode";;
    *) return;;
  esac
}

# Apply snapshot
apply_snapshot() {
  local source=$1
  echo -e "${GREEN}>>> Applying snapshot from ${source^^}...${NC}"
  
  # Stop services
  sudo systemctl stop story story-geth
  
  # Backup priv_validator_state.json
  echo -e "${CYAN}Backing up priv_validator_state.json...${NC}"
  cp $HOME/.story/story/data/priv_validator_state.json $HOME/.story/story/priv_validator_state.json.backup
  
  # Disable statesync
  sed -i.bak -E "s|^(enable[[:space:]]+=[[:space:]]+).*$|\1false|" $HOME/.story/story/config/config.toml
  
  # Remove old data
  rm -rf $HOME/.story/story/data
  rm -rf $HOME/.story/geth/aeneid/geth/chaindata
  
  # Download and extract based on source
  if [ "$source" == "itrocket" ]; then
    # Story snapshot
    echo -e "${CYAN}Downloading Story snapshot from ITRocket...${NC}"
    mkdir -p $HOME/.story/story/data
    curl -L $SNAPSHOT_ITROCKET_STORY | lz4 -dc - | tar -xf - -C $HOME/.story/story
    
    # Geth snapshot
    echo -e "${CYAN}Downloading Geth snapshot from ITRocket...${NC}"
    mkdir -p $HOME/.story/geth/aeneid/geth
    curl -L $SNAPSHOT_ITROCKET_GETH | lz4 -dc - | tar -xf - -C $HOME/.story/geth/aeneid/geth
  else
    # Story snapshot
    echo -e "${CYAN}Downloading Story snapshot from Auranode...${NC}"
    mkdir -p $HOME/.story/story/data
    aria2c -x 16 -s 16 -k 1M $SNAPSHOT_AURANODE_STORY -o Story_snapshot.lz4
    lz4 -d Story_snapshot.lz4 | pv | tar xv -C $HOME/.story/story > /dev/null
    
    # Geth snapshot
    echo -e "${CYAN}Downloading Geth snapshot from Auranode...${NC}"
    aria2c -x 16 -s 16 -k 1M $SNAPSHOT_AURANODE_GETH -o Geth_snapshot.lz4
    lz4 -d Geth_snapshot.lz4 | pv | tar xv -C $HOME/.story/geth/odyssey/geth > /dev/null
  fi
  
  # Restore priv_validator_state.json
  echo -e "${CYAN}Restoring priv_validator_state.json...${NC}"
  mv $HOME/.story/story/priv_validator_state.json.backup $HOME/.story/story/data/priv_validator_state.json
  
  # Start services
  sudo systemctl start story-geth story
  sudo systemctl enable story-geth story
  
  echo -e "${GREEN}Snapshot applied successfully!${NC}"
  echo -e "${YELLOW}Check sync status with: sudo journalctl -u story -f -o cat${NC}"
}

# Upgrade menu
upgrade_menu() {
  clear
  echo -e "${YELLOW}======================${NC}"
  echo -e "${YELLOW}    UPGRADE MENU      ${NC}"
  echo -e "${YELLOW}======================${NC}"
  echo -e "1. Upgrade Story"
  echo -e "2. Upgrade Story-Geth"
  echo -e "3. Upgrade Both"
  echo -e "4. Back to main menu"
  read -p "Choose option: " choice
  
  case $choice in
    1) upgrade_story;;
    2) upgrade_story_geth;;
    3) upgrade_story; upgrade_story_geth;;
    *) return;;
  esac
}

# Upgrade Story
upgrade_story() {
  echo -e "${GREEN}>>> Upgrading Story binary...${NC}"
  sudo systemctl stop story
  cd $HOME
  rm -rf story
  git clone https://github.com/piplabs/story
  cd story
  read -p "Enter version to install (eg v1.3.0): " version
  git checkout $version
  go build -o story ./client
  cp story $HOME/go/bin/
  sudo systemctl start story
  echo -e "${GREEN}Story upgraded to $version!${NC}"
}

# Upgrade Story-Geth
upgrade_story_geth() {
  echo -e "${GREEN}>>> Upgrading Story-Geth...${NC}"
  sudo systemctl stop story-geth
  cd $HOME
  read -p "Enter version to install (eg v1.1.0): " version
  wget -O story-geth https://github.com/piplabs/story-geth/releases/download/$version/geth-linux-amd64
  chmod +x story-geth
  mv story-geth $HOME/go/bin/story-geth
  sudo systemctl start story-geth
  echo -e "${GREEN}Story-Geth upgraded to $version!${NC}"
}

# State sync menu
state_sync_menu() {
  clear
  echo -e "${YELLOW}======================${NC}"
  echo -e "${YELLOW}    STATE SYNC MENU   ${NC}"
  echo -e "${YELLOW}======================${NC}"
  echo -e "1. Configure with ITRocket"
  echo -e "2. Configure with Auranode"
  echo -e "3. Back to main menu"
  read -p "Choose option: " choice
  
  case $choice in
    1) configure_state_sync "itrocket";;
    2) configure_state_sync "auranode";;
    *) return;;
  esac
}

# Configure state sync
configure_state_sync() {
  local provider=$1
  echo -e "${GREEN}>>> Configuring state sync with ${provider^^}...${NC}"
  
  # Stop services
  sudo systemctl stop story story-geth
  
  # Backup state file
  cp $HOME/.story/story/data/priv_validator_state.json $HOME/.story/story/priv_validator_state.json.backup
  
  # Clean data
  rm -rf $HOME/.story/story/data
  mkdir -p $HOME/.story/story/data
  mv $HOME/.story/story/priv_validator_state.json.backup $HOME/.story/story/data/priv_validator_state.json
  
  # Set provider-specific values
  if [ "$provider" == "itrocket" ]; then
    peers="01f8a2148a94f0267af919d2eab78452c90d9864@story-testnet-peer.itrocket.net:52656"
    SNAP_RPC=$RPC_ITROCKET
  else
    peers=$PEER_AURANODE
    SNAP_RPC=$RPC_AURANODE
  fi
  
  # Configure peers
  sed -i.bak -e "s/^persistent_peers *=.*/persistent_peers = \"$peers\"/" $HOME/.story/story/config/config.toml
  
  # Get trust params
  LATEST_HEIGHT=$(curl -s $SNAP_RPC/block | jq -r .result.block.header.height)
  BLOCK_HEIGHT=$((LATEST_HEIGHT - 1000))
  TRUST_HASH=$(curl -s "$SNAP_RPC/block?height=$BLOCK_HEIGHT" | jq -r .result.block_id.hash)
  
  echo -e "${CYAN}Trust Height: $BLOCK_HEIGHT${NC}"
  echo -e "${CYAN}Trust Hash: $TRUST_HASH${NC}"
  
  # Configure state sync
  sed -i.bak -E "s|^(enable[[:space:]]+=[[:space:]]+).*$|\1true| ;
  s|^(rpc_servers[[:space:]]+=[[:space:]]+).*$|\1\"$SNAP_RPC,$SNAP_RPC\"| ;
  s|^(trust_height[[:space:]]+=[[:space:]]+).*$|\1$BLOCK_HEIGHT| ;
  s|^(trust_hash[[:space:]]+=[[:space:]]+).*$|\1\"$TRUST_HASH\"| ;
  s|^(seeds[[:space:]]+=[[:space:]]+).*$|\1\"\"|" $HOME/.story/story/config/config.toml
  
  # Start services
  sudo systemctl restart story story-geth
  echo -e "${GREEN}State sync configured!${NC}"
  echo -e "${YELLOW}Monitor logs with: sudo journalctl -u story -f -o cat${NC}"
}

# Node sync status
node_sync_status() {
  echo -e "${GREEN}>>> Checking node sync status...${NC}"
  while true; do
    local_height=$(curl -s localhost:26657/status | jq -r '.result.sync_info.latest_block_height')
    network_height=$(curl -s $RPC_AURANODE/status | jq -r '.result.sync_info.latest_block_height')
    blocks_left=$((network_height - local_height))
    
    echo -e "Your node height: ${CYAN}$local_height${NC} | Network height: ${YELLOW}$network_height${NC} | Blocks left: ${RED}$blocks_left${NC}"
    sleep 5
  done
}

# Peer management
peer_menu() {
  clear
  echo -e "${YELLOW}======================${NC}"
  echo -e "${YELLOW}     PEER MENU        ${NC}"
  echo -e "${YELLOW}======================${NC}"
  echo -e "1. List current peers"
  echo -e "2. Add ITRocket peers"
  echo -e "3. Add Auranode peers"
  echo -e "4. Add custom peer"
  echo -e "5. Back to main menu"
  read -p "Choose option: " choice
  
  case $choice in
    1) list_peers;;
    2) add_peer "$PEER_ITROCKET";;
    3) add_peer "$PEER_AURANODE";;
    4) read -p "Enter peer (format: ID@IP:PORT): " custom_peer; add_peer "$custom_peer";;
    *) return;;
  esac
}

# List peers
list_peers() {
  echo -e "${GREEN}Current peers:${NC}"
  grep -A 1 "persistent_peers" $HOME/.story/story/config/config.toml
  echo -e "\n${YELLOW}Common peers:${NC}"
  echo -e "ITRocket: $PEER_ITROCKET"
  echo -e "Auranode: $PEER_AURANODE"
}

# Add peer
add_peer() {
  local peer=$1
  echo -e "${GREEN}>>> Adding peer: $peer${NC}"
  
  # Stop services
  sudo systemctl stop story
  
  # Add to config
  current_peers=$(grep 'persistent_peers' $HOME/.story/story/config/config.toml | cut -d '"' -f 2)
  if [[ ! $current_peers =~ $peer ]]; then
    new_peers="${current_peers},${peer}"
    sed -i "s|persistent_peers =.*|persistent_peers = \"$new_peers\"|" $HOME/.story/story/config/config.toml
    echo -e "${GREEN}Peer added successfully!${NC}"
  else
    echo -e "${YELLOW}Peer already exists!${NC}"
  fi
  
  # Start service
  sudo systemctl start story
}

# Delete node
delete_node() {
  echo -e "${RED}>>> Deleting node...${NC}"
  sudo systemctl stop story-geth
  sudo systemctl stop story
  sudo systemctl disable story-geth
  sudo systemctl disable story
  sudo rm /etc/systemd/system/story-geth.service
  sudo rm /etc/systemd/system/story.service
  sudo systemctl daemon-reload
  sudo rm -rf $HOME/.story
  sudo rm $HOME/go/bin/story-geth
  sudo rm $HOME/go/bin/story
  echo -e "${GREEN}Node deleted successfully!${NC}"
}

# Main loop
while true; do
  show_menu
  case $choice in
    1) auto_install;;
    2) snapshot_menu;;
    3) upgrade_menu;;
    4) state_sync_menu;;
    5) node_sync_status;;
    6) peer_menu;;
    7) delete_node;;
    8) echo -e "${GREEN}Exiting...${NC}"; exit 0;;
    *) echo -e "${RED}Invalid option!${NC}"; sleep 1;;
  esac
  read -p "Press Enter to continue..."
done