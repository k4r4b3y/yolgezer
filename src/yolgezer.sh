#!/data/data/com.termux/files/usr/bin/bash
set -xeuo pipefail
#
#!/data/data/com.termux/files/usr/bin/sh
# use bash in strict mode during development and debugging
# switch to posix compliant dash (sh) in production
#
# define directory locations
xmr_binary_dir=${HOME}/.local/bin/monero
xmr_config_dir=${HOME}/.config/monero
xmr_bc_dir=${HOME}/storage/external-1/bitmonero

# define resource URLs
xmr_dl_onion_64bit="http://dlmonerotqz47bjuthtko2k7ik2ths4w2rmboddyxw4tz4adebsmijid.onion/cli/androidarm8"
xmr_dl_onion_32bit="http://dlmonerotqz47bjuthtko2k7ik2ths4w2rmboddyxw4tz4adebsmijid.onion/cli/androidarm7"

# define working states

# install required packages
pkg upgrade -y -o Dpkg::Options::=--force-confnew && pkg install jq termux-api termux-services tor torsocks vim wget -y && pkg autoclean

# Setup the torrc file
#    change the SOCKSPort to 9055
#    to prevent conflict with orbot
sed -i 's/^SOCKSPort 9050/SOCKSPort 9055' ${PREFIX}/etc/tor/torrc

# Start tor as a termux-service
# sv-enable tor
sv-enable tor
sleep 7    # sleep to give time to tor

# pull the monero binaries
# 
# use torsocks -P 9055
mkdir -p ${xmr_binary_dir}
cd ${xmr_binary_dir}
torsocks -P 9055 wget ${xmr_dl_onion}

# unpack the binaries into proper place
#
#tar xjvf

# create the config file for the monero daemon
#

# run it and sync the blockchain
