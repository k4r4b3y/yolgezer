#!/data/data/com.termux/files/usr/bin/bash
set -xeuo pipefail
#
#!/data/data/com.termux/files/usr/bin/sh
# use bash in strict mode during development and debugging
# switch to posix compliant dash (sh) in production
#
# define directory locations
xmr_binary_dir="${HOME}/.local/bin/monero"
xmr_config_dir="${HOME}/.config/monero"
xmr_runit_dir="${HOME}/.config/sv/xmrd"
xmr_bc_dir="${HOME}/storage/external-1/bitmonero"

# ? TODO: add ${xmr_binary_dir} to the ${PATH}

# define resource URLs
xmr_dl_onion_64bit="http://dlmonerotqz47bjuthtko2k7ik2ths4w2rmboddyxw4tz4adebsmijid.onion/cli/androidarm8"
#xmr_dl_onion_32bit="http://dlmonerotqz47bjuthtko2k7ik2ths4w2rmboddyxw4tz4adebsmijid.onion/cli/androidarm7"

# define working states

# install required packages
pkg upgrade -y -o Dpkg::Options::=--force-confnew && pkg install jq p7zip proxychains-ng termux-api termux-services tor torsocks vim wget -y && pkg autoclean

# Setup the torrc file
#    change the SOCKSPort to 9055
#    to prevent conflict with orbot
if ! grep -q '^SOCKSPort 9055' "${PREFIX}/etc/tor/torrc"; then
  echo "SOCKSPort 9055" >> ${PREFIX}/etc/tor/torrc

fi

# Start tor as a termux-service
# sv-enable tor

case $(cat ${PREFIX}/var/service/tor/supervise/stat) in
	run ) echo "Tor is already running." ;;
	*) echo "Enabling tor daemon." && sv-enable tor && sleep 7 ;;
esac

# check the device architecture
case $(uname -m) in
	#arm | armv7l | armv8l ) MONERO_CLI_URL="https://downloads.getmonero.org/cli/androidarm7" ;;
	aarch64_be | aarch64 | armv8b ) xmr_dl_onion="${xmr_dl_onion_64bit}" ;;
	*) termux-toast -g bottom "Your device is not compatible- ARMv8 required"; exit 1 ;;
esac

# pull the monero binaries
mkdir -p ${xmr_binary_dir}

# use proxychains4
# setup its proper socks port
sed -i 's/^socks4.*127.0.0.1 9050$/socks5 127.0.0.1 9055/' ${PREFIX}/etc/proxychains.conf
proxychains4 -q wget -q --show-progress -O "${xmr_binary_dir}/android_monero_binaries" "${xmr_dl_onion}"

# extract and move the binaries
7z x "${xmr_binary_dir}/android_monero_binaries" -so | 7z x -aoa -si -ttar -o"${xmr_binary_dir}"
mv ${xmr_binary_dir}/monero-*/* ${xmr_binary_dir}/
rmdir ${xmr_binary_dir}/monero-*/
chmod +x ${xmr_binary_dir}/monero*


# check if a microsd card exists
[ -d ${HOME}/storage/external-1 ] && ( termux-setup-storage && xmr_bc_dir="${HOME}/storage/external-1/bitmonero" ) || xmr_bc_dir="${HOME}/.bitmonero" 
# TODO: check the available storage space before starting the monerod
mkdir -p ${xmr_bc_dir}

# create the config file for the monero daemon
#
mkdir -p ${xmr_config_dir}
cat << EOF > ${xmr_config_dir}/monerod.conf
# Data directory (blockchain db and indices)
data-dir=${xmr_bc_dir}

# Log file
log-file=/dev/null
max-log-file-size=0           # Prevent monerod from creating log files

# block-sync-size=50
prune-blockchain=1            # 1 to prune

# P2P (seeding) binds
p2p-bind-ip=0.0.0.0           # Bind to all interfaces. Default is local 127.0.0.1
p2p-bind-port=18080           # Bind to default port

# Restricted RPC binds (allow restricted access)
# Uncomment below for access to the node from LAN/WAN. May require port forwarding for WAN access
rpc-restricted-bind-ip=0.0.0.0
rpc-restricted-bind-port=18089

# Unrestricted RPC binds
rpc-bind-ip=127.0.0.1         # Bind to local interface. Default = 127.0.0.1
rpc-bind-port=18081           # Default = 18081
#confirm-external-bind=1      # Open node (confirm). Required if binding outside of localhost
#restricted-rpc=1             # Prevent unsafe RPC calls.

# Services
rpc-ssl=autodetect
no-zmq=1
no-igd=1                            # Disable UPnP port mapping
db-sync-mode=fast:async:1000000     # Switch to db-sync-mode=safe for slow but more reliable db writes

# Emergency checkpoints set by MoneroPulse operators will be enforced to workaround potential consensus bugs
# Check https://monerodocs.org/infrastructure/monero-pulse/ for explanation and trade-offs
#enforce-dns-checkpointing=1
disable-dns-checkpoints=1
enable-dns-blocklist=1


# Connection Limits
out-peers=32              # This will enable much faster sync and tx awareness; the default 8 is suboptimal nowadays
in-peers=32               # The default is unlimited; we prefer to put a cap on this
limit-rate-up=1048576     # 1048576 kB/s == 1GB/s; a raise from default 2048 kB/s; contribute more to p2p network
limit-rate-down=1048576   # 1048576 kB/s == 1GB/s; a raise from default 8192 kB/s; allow for faster initial sync
EOF

# run it and sync the blockchain
# create runit scripts
mkdir -p ${xmr_runit_dir}
cat << EOF > ${xmr_runit_dir}/run
#!/data/data/com.termux/files/usr/bin/sh
exec 2>&1
exec ${xmr_binary_dir}/monerod --non-interactive --config-file ${xmr_config_dir}/monerod.conf
EOF

mkdir -p ${xmr_runit_dir}/log
cat << EOF > ${xmr_runit_dir}/log/run
#!/data/data/com.termux/files/usr/bin/sh
svlogger="/data/data/com.termux/files/usr/share/termux-services/svlogger"
exec "\${svlogger}" "\$@"
EOF

# give executable permission
chmod +x ${xmr_runit_dir}/run
chmod +x ${xmr_runit_dir}/log/run

# create symlink to the $SVDIR
ln -sf ${xmr_runit_dir} ${SVDIR}/
sv-enable $(basename ${xmr_runit_dir})

# TODO: also add run conditions using termux-api for battery, and network state (wifi vs data)
