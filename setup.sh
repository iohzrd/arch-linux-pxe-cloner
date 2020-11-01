###############################################################################
# archlinux PXE cloner system 
###############################################################################

# install dependencies
pacman -S dnsmasq syslinux unzip

# prepare /srv/tftp diretory
mkdir /srv/tftp

# copy syslinux dependencies into /srv/tftp/
cp /usr/lib/syslinux/efi64/syslinux.efi /srv/tftp/
cp /usr/lib/syslinux/efi64/ldlinux.e64 /srv/tftp/

# download clonezilla zip distribution
wget https://netactuate.dl.sourceforge.net/project/clonezilla/clonezilla_live_stable/2.6.7-28/clonezilla-live-2.6.7-28-amd64.zip
# upzip clonezilla/live directory
unzip clonezilla-live-2.6.7-28-amd64.zip "live/*"
# copy clonezilla/live dependencies into /srv/tftp/
sudo cp live/* /srv/tftp/
# cleanup clonezilla
rm -rf clonezilla-live-2.6.7-28-amd64.zip live/

# create a default config for PXELINUX
mkdir /srv/tftp/pxelinux.cfg/
echo """DEFAULT Clonezilla-live

LABEL Clonezilla-live
 MENU LABEL Clonezilla Live (Ramdisk)
 KERNEL vmlinuz
 APPEND initrd=initrd.img boot=live config noswap nolocales edd=on nomodeset ocs_live_run=\"ocs-live-general\" ocs_live_extra_param=\"\" ocs_live_keymap=\"\" ocs_live_batch=\"no\" ocs_lang=\"\" vga=788 nosplash noprompt fetch=tftp://192.168.0.1/filesystem.squashfs
""" > /srv/tftp/pxelinux.cfg/default

# disable predictable interface names
touch /etc/udev/rules.d/80-net-setup-link.rules

# enable ip forwarding
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/30-ipforward.conf
echo 1 > /proc/sys/net/ipv4/ip_forward

# configure eth0
echo """[connection]
id=eth0
uuid=585646a7-65f1-47ed-aad3-0b1eceac10dd
type=ethernet
interface-name=eth0
permissions=

[ethernet]
mac-address-blacklist=

[ipv4]
address1=192.168.0.1/24
dns=
dns-search=
method=manual
route-metric=200
never-default=true

[ipv6]
addr-gen-mode=stable-privacy
dns-search=
method=disabled
never-default=true

[proxy]
""" > /etc/NetworkManager/system-connections/eth0.nmconnection
systemctl restart NetworkManager
nmcli c up eth0

# configure/start iptables
echo """*filter
:INPUT ACCEPT [6:687]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [1:32]
-A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -i eth0 -o wlan0 -j ACCEPT
COMMIT

*nat
:PREROUTING ACCEPT [1:242]
:INPUT ACCEPT [1:242]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 192.168.0.0/24 -j MASQUERADE
-A POSTROUTING -o wlan0 -j MASQUERADE
COMMIT
""" > /etc/iptables/iptables.rules
systemctl enable iptables
systemctl restart iptables

# configure/start dnsmasq dhcp and tftp server
echo """# Listen only to the specified interface
interface=eth0
bind-interfaces
listen-address=::1,127.0.0.1,192.168.0.1
server=1.1.1.1
server=8.8.8.8

# Set default gateway
dhcp-option=3,0.0.0.0

# Set DNS servers to announce
dhcp-option=6,0.0.0.0

# Don't function as dns server
port=0

# dhcp ip range
dhcp-range=192.168.0.2,192.168.0.252,12h

# tftp server setup
enable-tftp
tftp-root=/srv/tftp

# PXE bootloader
dhcp-match=set:efi-x86_64,option:client-arch,7
dhcp-match=set:efi-x86_64,option:client-arch,9
dhcp-boot=tag:efi-x86_64,syslinux.efi

# Log extra information about dhcp transactions (for debug purposes)
log-dhcp
""" > /etc/dnsmasq.conf
systemctl enable dnsmasq
systemctl restart dnsmasq
