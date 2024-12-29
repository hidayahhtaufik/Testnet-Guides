#!/bin/bash

LOGO="

                                                                  ___           
                                                                 (   )          
  .---.   ___  ___   ___ .-.      .---.   ___ .-.     .--.     .-.| |    .--.   
 / .-, \ (   )(   ) (   )   \    / .-, \ (   )   \   /    \   /   \ |   /    \  
(__) ; |  | |  | |   | ' .-. ;  (__) ; |  |  .-. .  |  .-. ; |  .-. |  |  .-. ; 
  .'`  |  | |  | |   |  / (___)   .'`  |  | |  | |  | |  | | | |  | |  |  | | | 
 / .'| |  | |  | |   | |         / .'| |  | |  | |  | |  | | | |  | |  |  |/  | 
| /  | |  | |  | |   | |        | /  | |  | |  | |  | |  | | | |  | |  |  ' _.' 
; |  ; |  | |  ; '   | |        ; |  ; |  | |  | |  | '  | | | '  | |  |  .'.-. 
' `-'  |  ' `-'  /   | |        ' `-'  |  | |  | |  '  `-' / ' `-'  /  '  `-' / 
`.__.'_.   '.__.'   (___)       `.__.'_. (___)(___)  `.__.'   `.__,'    `.__.'  
                                                                                
                                                                                
"

echo "$LOGO"

# Prompt for MONIKER, STORY_PORT, and Indexer option
read -p "Enter your moniker: " MONIKER
read -p "Enter your preferred port number: (leave empty to use default: 26)" STORY_PORT
if [ -z "$STORY_PORT" ]; then
    STORY_PORT=26
fi
read -p "Do you want to enable the indexer? (yes/no): " ENABLE_INDEXER

# Stop and remove existing Story node
sudo systemctl daemon-reload
sudo systemctl stop story story-geth
sudo systemctl disable story
sudo systemctl disable story-geth
sudo rm -rf /etc/systemd/system/story.service
sudo rm -rf /etc/systemd/system/story-geth.service
sudo rm -r $HOME/go/bin/story
sudo rm -r $HOME/go/bin/story-geth $HOME/go/bin/geth
sudo rm -rf $HOME/.story
sed -i "/STORY_/d" $HOME/.bash_profile

# 1. Install dependencies for building from source
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y curl git jq build-essential gcc unzip wget lz4 openssl libssl-dev pkg-config protobuf-compiler clang cmake llvm llvm-dev

# 2. Install Go
cd $HOME && ver="1.22.0"
wget "https://golang.org/dl/go$ver.linux-amd64.tar.gz"
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf "go$ver.linux-amd64.tar.gz"
rm "go$ver.linux-amd64.tar.gz"
echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> ~/.bash_profile
source ~/.bash_profile
go version

# 3. Install Cosmovisor
go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@latest

# 4. Set environment variables
export MONIKER=$MONIKER
export STORY_CHAIN_ID="odyssey"
export STORY_PORT=$STORY_PORT
echo "export MONIKER=\"$MONIKER\"" >> $HOME/.bash_profile
echo "export STORY_CHAIN_ID=\"odyssey\"" >> $HOME/.bash_profile
echo "export STORY_PORT=\"$STORY_PORT\"" >> $HOME/.bash_profile
source $HOME/.bash_profile

# 5. Download Geth and Consensus Client binaries
cd $HOME

# Geth binary
mkdir -p story-geth-v0.11.0
wget -O story-geth-v0.11.0/geth-linux-amd64 https://github.com/piplabs/story-geth/releases/download/v0.11.0/geth-linux-amd64
cp story-geth-v0.11.0/geth-linux-amd64 $HOME/go/bin/geth
sudo chown -R $USER:$USER $HOME/go/bin/geth
sudo chmod +x $HOME/go/bin/geth

# Consensus client binary
mkdir -p story-v0.13.0
wget -p $HOME/story-v0.13.0 https://github.com/piplabs/story/releases/download/v0.13.0/story-linux-amd64 -O $HOME/story-v0.13.0/story
cp story-v0.13.0/story $HOME/go/bin/story
sudo chown -R $USER:$USER $HOME/go/bin/story
sudo chmod +x $HOME/go/bin/story

# 6. Initialize the app
story init --network $STORY_CHAIN_ID --moniker $MONIKER

# 7. Set custom ports in config.toml and story.toml
sed -i.bak -e "s%laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:${STORY_PORT}656\"%;
s%prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":${STORY_PORT}660\"%;
s%proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:${STORY_PORT}658\"%;
s%laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:${STORY_PORT}657\"%" $HOME/.story/story/config/config.toml

sed -i.bak -e "s%engine-endpoint = \"http://localhost:8551\"%engine-endpoint = \"http://localhost:${STORY_PORT}551\"%;
s%api-address = \"127.0.0.1:1317\"%api-address = \"127.0.0.1:${STORY_PORT}317\"%" $HOME/.story/story/config/story.toml

# 8. Add peers to the config.toml
peers="07ab4164e1d0ee17c565542856ac58981537156f@185.16.38.165:42656,69a0bad6288d0f629b4107dd4efc2948f06eb7fc@168.119.10.134:26656,28caef23d717f765482c7a2245b9c5e5b7dd2c2d@149.50.114.127:26156,c11234e1f3b4c6866161bdada6805aa7af5f2f47@212.47.76.248:26656,139ad8e25b7b1ffec35b21701efd3097cbabdee8@38.242.158.60:26156,bd8f016ee518f9f041507d7f6432318a09b726cf@51.83.143.129:32175,59c93f3cb69a0e13898ac4910748cd8858cdeeb7@167.235.94.84:26656,6e3423d9a8128645d5cad9165e26fa2eac66d150@93.190.138.116:26656,ffe2448f8bdc66921ed417afecc70c066adcd08e@62.84.178.212:26656,a4f0d9f44b56dcc8f98a714e8efcd87ac71c6652@65.109.26.242:25556,46e08dd5e5f818785e99d34dd81d4aa5f3d4ba9e@157.173.115.220:26656,743db14c635c8019027b734ed4f809e8be0bc71b@185.245.183.145:26156,e488f448c575a4f0ae4f62883b297acaf681900c@149.50.113.243:26156,1b6637e4c7cc1c0d85ddb20c66d2382b66ea6e92@95.216.12.106:41656,64a43b819fb765426c4714221be095f838320bb8@85.208.51.224:26656"
sed -i -e "s|^persistent_peers *=.*|persistent_peers = \"$peers\"|" $HOME/.story/story/config/config.toml
echo $peers

# 9. Enable or disable indexer based on user input
if [ "$ENABLE_INDEXER" = "yes" ]; then
    sed -i -e 's/^indexer = "null"/indexer = "kv"/' $HOME/.story/story/config/config.toml
    echo "Indexer enabled."
else
    sed -i -e 's/^indexer = "kv"/indexer = "null"/' $HOME/.story/story/config/config.toml
    echo "Indexer disabled."
fi

# 10. Export Private key
story validator export --evm-key-path $HOME/.story/story/config/private_key.txt --export-evm-key
PRIVATE_KEY=$(grep -oP '(?<=PRIVATE_KEY=).*' $HOME/.story/story/config/private_key.txt)

# 11. Initialize Cosmovisor and create a symlink to the latest consensus client version in the Go directory
echo "export DAEMON_NAME=story" >> $HOME/.bash_profile
echo "export DAEMON_HOME=$(find "$HOME/.story" -type d -name "story" -print -quit)" >> $HOME/.bash_profile
source $HOME/.bash_profile
cosmovisor init $HOME/go/bin/story
cd $HOME/go/bin/
sudo rm -r $HOME/go/bin/story
ln -s $HOME/.story/story/cosmovisor/current/bin/story story
sudo chown -R $USER:$USER $HOME/go/bin/story
sudo chown -R $USER:$USER $HOME/.story
sudo chmod +x $HOME/go/bin/story
mkdir -p $HOME/.story/story/cosmovisor/upgrades
mkdir -p $HOME/.story/story/cosmovisor/backup
cd $HOME

# 12. Define Cosmovisor paths for the consensus client
input1=$(which cosmovisor)
input2=$(find "$HOME/.story" -type d -name "story" -print -quit)
input3=$(find "$HOME/.story/story/cosmovisor" -type d -name "backup" -print -quit)
echo "export DAEMON_NAME=story" >> $HOME/.bash_profile
echo "export DAEMON_HOME=$input2" >> $HOME/.bash_profile
echo "export DAEMON_DATA_BACKUP_DIR=$input3" >> $HOME/.bash_profile
source $HOME/.bash_profile
echo "Cosmovisor path: $input1"
echo "Story home: $input2"
echo "Backup directory: $input3"

# 13. Create systemd service files for the consensus and Geth clients

# Consensus service file
sudo tee /etc/systemd/system/story.service > /dev/null <<EOF
[Unit]
Description=Cosmovisor Story Node
After=network.target

[Service]
User=${USER}
Type=simple
WorkingDirectory=${HOME}/.story/story
ExecStart=${input1} run run
StandardOutput=journal
StandardError=journal
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
LimitNPROC=65536
Environment="DAEMON_NAME=story"
Environment="DAEMON_HOME=${input2}"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="DAEMON_DATA_BACKUP_DIR=${input3}"
Environment="UNSAFE_SKIP_BACKUP=true"

[Install]
WantedBy=multi-user.target
EOF

# Geth service file
sudo tee /etc/systemd/system/story-geth.service > /dev/null <<EOF
[Unit]
Description=Story Geth Node
After=network-online.target

[Service]
User=$USER
ExecStart=$(which geth) --odyssey --syncmode full --http --http.api eth,net,web3,engine --http.vhosts '*' --http.addr 0.0.0.0 --http.port ${STORY_PORT}545 --ws --ws.api eth,web3,net,txpool --ws.addr 0.0.0.0 --ws.port ${STORY_PORT}546 --authrpc.port ${STORY_PORT}551
StandardOutput=journal
StandardError=journal
Restart=on-failure
RestartSec=3
LimitNOFILE=65536
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
EOF

# 14. Start the node
sudo systemctl daemon-reload
sudo systemctl enable story-geth story
sudo systemctl restart story-geth story

# 14. Confirmation message for installation completion
if systemctl is-active --quiet story && systemctl is-active --quiet story-geth; then
    echo "Node installation and services started successfully!"
else
    echo "Node installation failed. Please check the logs for more information."
fi

# show the full logs
echo "sudo journalctl -u story-geth -u story -fn 100"