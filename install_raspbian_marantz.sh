# Make sure raspbian is updated
sudo apt-get -y update && sudo apt-get -y upgrade

# Intall all build essentials
sudo apt -y install build-essential git xmltoman autoconf automake libtool libdaemon-dev libpopt-dev libconfig-dev libasound2-dev libpulse-dev avahi-daemon libavahi-client-dev libssl-dev libsoxr-dev

cd ~

# Build and set-up shairport-sync
git clone https://github.com/mikebrady/shairport-sync.git
cd shairport-sync
autoreconf -i -f
./configure --sysconfdir=/etc --with-alsa --with-pa --with-pipe --with-avahi --with-ssl=openssl --with-metadata --with-soxr --with-systemd
make
sudo make install

# Enable start service
sudo systemctl enable shairport-sync.service
sudo service shairport-sync start

# Create configuration file
cat <<EOT >> /etc/shairport-sync.conf
// General Settings
general =
{
        name = "Marantz";
        volume_control_profile = "flat";
        ignore_volume_control = "yes";
        run_this_when_volume_is_set = "/home/pi/lirc-volume-control/set_lirc_volume.sh ";

};
EOT

# Set-up hifiberry
echo "dtoverlay=hifiberry-dac" >> /boot/config.txt
cat <<EOT >> /etc/asound.conf
pcm.!default  {
	type hw card 0
}
ctl.!default {
	type hw card 0
}
EOT

# Add LIRC service
sudo apt-get -y install lirc
echo "dtoverlay=lirc-rpi,gpio_in_pin=22,gpio_out_pin=23" >> /boot/config.txt
# Change driver to default (instead of devinput)
sed -e 's/\(driver[[:blank:]]*=[[:blank:]]*\)devinput/\1default/g' /etc/lirc/lirc_options.conf > /etc/lirc/lirc_options.conf
# Add configuration file for Marantz devices
sudo mv RC8000PM.lirc.conf /etc/lirc/lircd.conf.d/

# Add LIRC volume control
git clone "https://github.com/tjibbevanderlaan/lirc-volume-control.git"
cd lirc-volume-control
sudo mv lirc-volume-control.service /etc/systemd/system
chmod +x lirc-volume-control.sh
chmod +x set_lirc_volume.sh
sudo apt-get -y install bc
sudo systemctl enable lirc-volume-control
sudo service lirc-volume-control start

# Set-up spotify
wget "https://github.com/Spotifyd/spotifyd/releases/download/v0.2.5/spotifyd-2019-02-25-armv6.zip"
unzip spotifyd-2019-02-25-armv6.zip
mv spotifyd-2019-02-25-armv6/spotifyd /usr/bin
rm -r spotifyd-2019-02-25-armv6

# Create configuration file
cat <<EOT >> /etc/spotifyd.conf
[global]
backend = alsa
volume-control = alsa_linear
device_name = Marantz # Cannot contain spaces
bitrate = 320
volume-normalisation = true
EOT

# Create and enable start service
cat <<EOT >> /etc/systemd/system/spotifyd.service
[Unit]
Description=A spotify playing daemon
Documentation=https://github.com/Spotifyd/spotifyd
Wants=sound.target
After=sound.target
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/bin/spotifyd --no-daemon
Restart=always
RestartSec=12

[Install]
WantedBy=default.target
EOT

sudo systemctl enable spotifyd.service
sudo service spotifyd start
