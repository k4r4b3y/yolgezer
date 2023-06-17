#!/data/data/com.termux/files/usr/bin/bash
set -xeuo pipefail
#
#!/data/data/com.termux/files/usr/bin/sh
# use bash in strict mode during development and debugging
# switch to posix compliant dash (sh) in production
#


####################################
# --- PKG UPGRADE && PKG INSTALL ---
####################################

pkg upgrade -y -o Dpkg::Options::=--force-confnew && pkg install jq p7zip proxychains-ng termux-api termux-services tor torsocks vim wget -y && pkg autoclean


##############################
# --- VARIABLE DEFINITIONS --- 
##############################

xmr_binary_dir="${HOME}/.local/bin/monero"         # the directory where the executables reside
xmr_config_dir="${HOME}/.config/monero"            # the directory where the monerod config file is
xmr_runit_dir="${HOME}/.config/sv/xmrd"            # the directory where the runit service files are
xmr_bc_dir="${HOME}/storage/external-1/bitmonero"  # the directory where the blockchain will be stored
xmr_dl_onion_64bit="http://dlmonerotqz47bjuthtko2k7ik2ths4w2rmboddyxw4tz4adebsmijid.onion/cli/androidarm8"
#xmr_dl_onion_32bit="http://dlmonerotqz47bjuthtko2k7ik2ths4w2rmboddyxw4tz4adebsmijid.onion/cli/androidarm7"
# check the device architecture
case $(uname -m) in
	#arm | armv7l | armv8l ) MONERO_CLI_URL="https://downloads.getmonero.org/cli/androidarm7" ;;
	aarch64_be | aarch64 | armv8b ) xmr_dl_onion="${xmr_dl_onion_64bit}" ;;
	*) termux-toast -g bottom "Your device is not compatible- ARMv8 required"; exit 1 ;;
esac
# check if a microsd card exists
termux-setup-storage
while [ ! -d "${HOME}/storage" ]; do
  sleep 1    # wait until the user has granted internal storage permision
done
[ -d ${HOME}/storage/external-1 ] && ( xmr_bc_dir="${HOME}/storage/external-1/bitmonero" ) || xmr_bc_dir="${HOME}/.bitmonero" 
# TODO: check the available storage space before starting the monerod
mkdir -p ${xmr_bc_dir}


##########################
# --- SETUP TOR DAEMON ---
##########################

# change the SOCKSPort to 9055
# to prevent conflict with orbot
if ! grep -q '^SOCKSPort 9055' "${PREFIX}/etc/tor/torrc"; then
  echo "SOCKSPort 9055" >> ${PREFIX}/etc/tor/torrc
fi

cat << EOF >> ${PREFIX}/etc/tor/torrc
# monerod hidden service
HiddenServiceDir /data/data/com.termux/files/usr/var/lib/tor/xmrd/ 
HiddenServicePort 18089 127.0.0.1:18089    # For wallets connecting over RPC
HiddenServicePort 18083 127.0.0.1:18083    # For other nodes
EOF
mkdir -p /data/data/com.termux/files/usr/var/lib/tor/xmrd/
# Start tor as a termux-service
case $(cat ${PREFIX}/var/service/tor/supervise/stat) in
	run ) echo "Tor is already running." && sv restart tor ;;
	*) echo "Enabling tor daemon." && sv-enable tor && sleep 7 ;;
esac
# TODO: put here the one-liner that defines ${xmr_hidden_address}


##################################
# --- DOWNLOAD MONERO BINARIES ---
##################################

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


####################################
# --- CREATE RUNIT SERVICE FILES ---
####################################

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

# TODO: also add run conditions using termux-api for battery, and network state (wifi vs data)


##################################
# --- CREATE MONEROD.CONF FILE ---
##################################

mkdir -p ${xmr_config_dir}
cat << EOF > ${xmr_config_dir}/monerod.conf
# --- DATA ---
# Data directory (blockchain db and indices)
data-dir=${xmr_bc_dir}
# Log file
# we will be using the stdout of the
# monerod for logs with svlogd
log-file=/dev/null
max-log-file-size=0                 # Prevent monerod from creating log files

# --- PERFORMANCE --- 
block-sync-size=0                   # keep it at default
prune-blockchain=1                  # 1 to prune
sync-pruned-blocks=1                # only download the pruned blocks
disable-dns-checkpoints=1
enable-dns-blocklist=1
db-sync-mode=fast:async:25000000    # Switch to db-sync-mode=safe for slow but more reliable db writes
# also try "fastest:async:1000000" to see if it speeds up
max-concurrency=2		                # Max threads. Avoid overheating (default 4)

# --- NETWORK ---
no-zmq=1                     # unnecessary for now
no-igd=1                     # Disable UPnP port mapping
public-node=1                # reachable by anyone who knows the tor hidden service address
confirm-external-bind=1      # Open node (confirm). Required if binding outside of localhost
restricted-rpc=1             # Prevent unsafe RPC calls.
rpc-ssl=disabled             # we'll keep the node accessible over tor which itself is encrypted
disable-rpc-ban=1            # Be more generous to wallets connecting
# P2P (seeding) binds
# for the p2p comms
p2p-bind-ip=0.0.0.0           # Bind to all interfaces. Default is local 127.0.0.1
p2p-bind-port=18080           # Bind to default port
# Restricted RPC binds (allow restricted access)
# for external wallets connecting to us over tor network
# we will forward the incoming tor hidden service connections
# to this port on the machine
rpc-restricted-bind-ip=0.0.0.0
rpc-restricted-bind-port=18089
# Unrestricted RPC binds
# for local RPC calls from the termux itself
rpc-bind-ip=127.0.0.1         # Bind to local interface. Default = 127.0.0.1
rpc-bind-port=18081           # Default = 18081
# Connection Limits
out-peers=32                  # This will enable much faster sync and tx awareness; the default 8 is suboptimal nowadays
in-peers=32                   # The default is unlimited; we prefer to put a cap on this
limit-rate-up=1048576         # 1048576 kB/s == 1GB/s; a raise from default 2048 kB/s; contribute more to p2p network
limit-rate-down=1048576       # 1048576 kB/s == 1GB/s; a raise from default 8192 kB/s; allow for faster initial sync

# --- TOR ---
tx-proxy=tor,127.0.0.1:9055,16,disable_noise   # we set port 9055 to prevent orbot conflicts
anonymous-inbound=${xmr_hidden_address}:18083,127.0.0.1:18083,16
proxy=127.0.0.1:9055
pad-transactions=1
EOF


################################
# --- ENABLE MONEROD SERVICE ---
################################

sv-enable $(basename ${xmr_runit_dir})
