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
xmr_bc_dir="${HOME}/storage/external-1/bitmonero"

# define resource URLs
xmr_dl_onion_64bit="http://dlmonerotqz47bjuthtko2k7ik2ths4w2rmboddyxw4tz4adebsmijid.onion/cli/androidarm8"
#xmr_dl_onion_32bit="http://dlmonerotqz47bjuthtko2k7ik2ths4w2rmboddyxw4tz4adebsmijid.onion/cli/androidarm7"

# define working states

# install required packages
pkg upgrade -y -o Dpkg::Options::=--force-confnew && pkg install jq p7zip termux-api termux-services tor torsocks vim wget -y && pkg autoclean

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
	*) termux-toast -g bottom "Your device is not compatible- ARMv8"; exit 1 ;;
esac

# pull the monero binaries
# 
# use torsocks -P 9055
mkdir -p ${xmr_binary_dir}
cd ${xmr_binary_dir}
#torsocks -P 9055 wget -q --show-progress -O android_monero_binaries "${xmr_dl_onion}"
# Download the file using wget with torsocks
download_file() {
  local file_url="\$1"
  local output_file="\$2"

  torsocks -P 9055 wget "${file_url}" -O "${output_file}" &
  local process_id=$!
  wait $process_id
}

# Download the file and ensure it completes before moving on to the next command
download_file "${xmr_dl_onion}" "android_monero_binaries"
7z x "android_monero_binaries" -so | 7z x -aoa -si -ttar
chmod +x monero-*/monero*

# create the config file for the monero daemon
#

# run it and sync the blockchain
