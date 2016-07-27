#!/bin/bash

# https://infosecspeakeasy.org/t/howto-build-a-cuckoo-sandbox/27

#-------------------------------------------#
#      Install Cuckoo Sandbox Version       #
#          Tested on Ubuntu 16.04           #
#-------------------------------------------#

function usage
{
	echo 'Usage: $0 <path> <password>' 
	echo '---Optional Arguments---'
	echo 'Cuckoo Install Path -> Example /opt' #option 1
	echo 'Database Password -> PostgreSQL password' #option 2
	exit
}

#Variables defined by options at runtime
cuckoo_path=${1:-/opt}
passwd=${2:-$rand_passwd}
rand_passwd=$(date +%s | sha256sum | base64 | head -c 32 ; echo)

cuckoo_passwd=$passwd
db_passwd=\'$passwd\'


#Additional variables that might be used
my_ip=$(ip route show | awk '(NR == 2) {print $9}')

function deps
{

echo -e '\e[35m[+] Installing Dependencies \e[0m'

	#Update, upgrade, dist-upgrade, and autoremove
	apt-get update && apt-get upgrade -y && apt-get dist-upgrade -y && apt-get autoremove -y >/dev/null 2>&1

	#Basic dependencies
	apt-get install mongodb python python-dev python-pip python-m2crypto swig -y >/dev/null 2>&1
	apt-get install libvirt-dev upx-ucl libssl-dev unzip p7zip-full libgeoip-dev libjpeg-dev -y >/dev/null 2>&1
	apt-get install mono-utils ssdeep libfuzzy-dev libimage-exiftool-perl openjdk-8-jre-headless -y >/dev/null 2>&1

	#Additional dependencies for malheur
	apt-get install uthash-dev libtool libconfig-dev libarchive-dev autoconf automake checkinstall -y >/dev/null 2>&1

	#Upgrade pip
	pip install --upgrade pip >/dev/null 2>&1

	#To generate PDF reports
	apt-get install wkhtmltopdf xvfb xfonts-100dpi -y >/dev/null 2>&1

echo -e '\e[35m[+] Installing Yara \e[0m'

	#Yara Dependencies
	apt-get install libjansson-dev libmagic-dev bison -y >/dev/null 2>&1

	#Configure Yara for Cuckoo and Magic and then install
	cd /opt
	git clone https://github.com/plusvic/yara.git
	cd yara
	./bootstrap.sh >/dev/null 2>&1
	./configure --enable-cuckoo --enable-magic >/dev/null 2>&1
	make >/dev/null 2>&1
	make install >/dev/null 2>&1

	#Install yara-python
	pip install yara-python >/dev/null 2>&1

echo -e '\e[35m[+] Installing ClamAV \e[0m'

	#Install ClamAV
	apt-get install clamav clamav-daemon clamav-freshclam -y >/dev/null 2>&1
    
echo -e '\e[35m[+] Installing Pydeep \e[0m'    

	#Install Pydeep
	pip install git+https://github.com/kbandla/pydeep.git >/dev/null 2>&1

echo -e '\e[35m[+] Installing Malheur \e[0m'

	#Install malheur
	cd /opt
	git clone https://github.com/rieck/malheur.git
	cd malheur
	./bootstrap >/dev/null 2>&1
	./configure --prefix=/usr >/dev/null 2>&1
	make >/dev/null 2>&1
	make install >/dev/null 2>&1

echo -e '\e[35m[+] Installing Volatility \e[0m'

	#Install volatility
	apt-get install python-pil -y >/dev/null 2>&1
	pip install distorm3 pycrypto openpyxl >/dev/null 2>&1
	apt-get install volatility -y >/dev/null 2>&1

echo -e '\e[35m[+] Installing PyV8 Javascript Engine (this will take some time) \e[0m'

	#Additional dependencies for PyV8
	apt-get install libboost-all-dev -y >/dev/null 2>&1

	#Install PyV8
	cd /opt
	git clone https://github.com/buffer/pyv8.git
	cd pyv8
	python setup.py build >/dev/null 2>&1
	python setup.py install >/dev/null 2>&1

echo -e '\e[35m[+] Configuring TcpDump \e[0m'

	#Configure tcpdump
	chmod +s /usr/sbin/tcpdump

echo -e '\e[35m[+] Installing Suricata \e[0m'

	#Install Suricata
	apt-get install suricata -y >/dev/null 2>&1
	echo "alert http any any -> any any (msg:\"FILE store all\"; filestore; noalert; sid:15; rev:1;)"  | sudo tee /etc/suricata/rules/cuckoo.rules

echo -e '\e[35m[+] Installing ETUpdate \e[0m'
 
	#Install ETUpdate
	cd /opt
	git clone https://github.com/seanthegeek/etupdate.git
	cp etupdate/etupdate /usr/sbin

	#Download rules
	/usr/sbin/etupdate -V 

}

function postgres
{

echo -e '\e[35m[+] Installing PostgreSQL \e[0m'

	#Install PostgreSQL
	apt-get install postgresql-9.5 postgresql-contrib-9.5 libpq-dev -y >/dev/null 2>&1
	pip install psycopg2 >/dev/null 2>&1

echo -e '\e[35m[+] Configure PostgreSQL DB \e[0m'

	su - postgres <<EOF
psql -c "CREATE USER cuckoo WITH PASSWORD $db_passwd;"
psql -c "CREATE DATABASE cuckoo;"
psql -c "GRANT ALL PRIVILEGES ON DATABASE cuckoo to cuckoo;"
EOF

}

function machinery
{

echo -e '\e[35m[+] Installing KVM \e[0m'

	#Install KVM and virt-manager
	apt-get install qemu-kvm libvirt-bin virt-manager libgl1-mesa-glx -y >/dev/null 2>&1

	#Add current user to kvm and libvirt groups for admin
	usermod -a -G kvm $USER
	usermod -a -G libvirtd $USER

	#Deactivate default network
	virsh net-destroy default

	#Remove default network from libvirt configuration
	virsh net-undefine default

	#Create cuckoo network configuration file
	cat >/tmp/cuckoo_net.xml <<EOF
<network>
	<name>cuckoo</name>
	<bridge name='virbr0' stp='on' delay='0'/>
	<domain name='cuckoo'/>
	<ip address='192.168.100.1' netmask='255.255.255.0'>
<dhcp>
	<range start='192.168.100.128' end='192.168.100.254'/>
</dhcp>
</ip>
</network>
EOF

	#Create new cuckoo network from xml configuration
	virsh net-define --file /tmp/cuckoo_net.xml

	#Set cuckoo network to autostart
	virsh net-autostart cuckoo

	#Start cuckoo network
	virsh net-start cuckoo

}

function create_cuckoo_user
{

echo -e '\e[35m[+] Creating cuckoo user \e[0m'

	#Creates cuckoo user and sets password to DB password for now
	adduser cuckoo --gecos "First Last,RoomNumber,WorkPhone,HomePhone" --disabled-password
	echo "cuckoo:$cuckoo_passwd" | chpasswd
	usermod -L cuckoo
	usermod -a -G kvm cuckoo
	usermod -a -G libvirtd cuckoo
	usermod -a -G cuckoo $USER
}

function cuckoo_mod_install
{

echo -e '\e[35m[+] Installing Modified version of Cuckoo \e[0m'

	#Option to install modified version
	su - cuckoo <<EOF
cd
wget https://bitbucket.org/mstrobel/procyon/downloads/procyon-decompiler-0.5.30.jar
git clone https://github.com/daniel-gallagher/cuckoo-modified.git
mkdir vmshared
cp cuckoo-modified/agent/agent.py vmshared/agent.pyw
EOF

	chmod ug=rwX,o=rX /home/cuckoo/vmshared
	mv /home/cuckoo/cuckoo-modified $cuckoo_path/cuckoo
	pip install -r $cuckoo_path/cuckoo/requirements.txt >/dev/null 2>&1
	cp $cuckoo_path/cuckoo/extra/suricata-cuckoo.yaml /etc/suricata/suricata-cuckoo.yaml

echo -e '\e[35m[+] Installing Cuckoo signatures \e[0m'

	su - cuckoo <<EOF
cd $cuckoo_path/cuckoo/utils
./community.py -afw
EOF

echo -e '\e[35m[+] Modifing Cuckoo config \e[0m'

	sed -i -e "s@connection =@connection = postgresql://cuckoo:$passwd\@localhost:5432/cuckoo@" $cuckoo_path/cuckoo/conf/cuckoo.conf

	chown -R cuckoo:cuckoo $cuckoo_path/cuckoo
}

function nginx
{

echo -e '\e[35m[+] Installing nginx \e[0m'

	#Install nginx
	apt-get install nginx apache2-utils -y >/dev/null 2>&1

echo -e '\e[35m[+] Configuring nginx \e[0m'

	#Remove default nginx configuration
	rm /etc/nginx/sites-enabled/default

	#Create cuckoo web server config
	cp $cuckoo_path/cuckoo/extra/nginx_config /etc/nginx/sites-available/cuckoo

	#Modify nginx IP for web interface
	sed -i -e "s@listen IP_Address\:443@listen $my_ip\:443@" /etc/nginx/sites-available/cuckoo
	sed -i -e "s@listen IP_Address\:80@listen $my_ip\:80@" /etc/nginx/sites-available/cuckoo
	sed -i -e "s@listen IP_Address\:4343@listen $my_ip\:4343@" /etc/nginx/sites-available/cuckoo
	sed -i -e "s@allow IP_Address@allow $my_ip@" /etc/nginx/sites-available/cuckoo

	#Enable cuckoo nginx config
	ln -s /etc/nginx/sites-available/cuckoo /etc/nginx/sites-enabled/cuckoo

#!!!FINISH!!! #Create nginx user for web auth
	#htpasswd -c /etc/nginx/htpasswd $USER

	#Secure htpasswd file
	#chown root:www-data /etc/nginx/htpasswd
	#chmod u=rw,g=r,o= /etc/nginx/htpasswd


}

function self_ssl
{

echo -e '\e[35m[+] Creating Self-signed SSL Certificate \e[0m'

	#Create ssl key folder
	mkdir /etc/nginx/ssl

	#Generate self-signed certificate
	openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/cuckoo.key -out /etc/nginx/ssl/cuckoo.crt -subj "/C=XX/ST=XX/L=XX/O=IT/CN=$my_ip"
	
	#Generate Diffie-Hellman (DH) parameters. This takes a long time!
	openssl dhparam -out /etc/nginx/ssl/dhparam.pem 2048

	#Secure SSL keys
	chown -R root:www-data /etc/nginx/ssl
	chmod -R u=rX,g=rX,o= /etc/nginx/ssl

	#Restart nginx
	service nginx restart

}

function misc_apps
{

echo -e '\e[35m[+] Installing Inetsim \e[0m'

	#Install inetsim
	cd /tmp
	wget http://www.inetsim.org/debian/binary/inetsim_1.2.5-1_all.deb

	#Install additional inetsim dependencies
	apt-get install libcgi-fast-perl libcgi-pm-perl libdigest-hmac-perl libfcgi-perl libio-multiplex-perl libio-socket-inet6-perl libipc-shareable-perl libnet-cidr-perl libnet-dns-perl libnet-ip-perl libnet-server-perl libsocket6-perl liblog-log4perl-perl -y >/dev/null 2>&1
	dpkg -i inetsim_1.2.5-1_all.deb >/dev/null 2>&1

	#Copy default inetsim config
	cp $cuckoo_path/cuckoo/extra/inetsim.conf /etc/inetsim/inetsim.conf

	#Enable inetsim in default config
	sed -i -e 's@ENABLED=0@ENABLED=1@' /etc/default/inetsim

	#Restart inetsim
	service inetsim restart

echo -e '\e[35m[+] Installing Tor Proxy \e[0m'

	#Install tor
	apt-get install tor -y >/dev/null 2>&1

	#Copy default tor config
	cp $cuckoo_path/cuckoo/extra/torrc /etc/tor/torrc

	#Restart tor
	service tor restart

echo -e '\e[35m[+] Installing Privoxy \e[0m'

	#Install Privoxy
	apt-get install privoxy -y >/dev/null 2>&1

	#Copy default privoxy config
	cp $cuckoo_path/cuckoo/extra/privoxy_config /etc/privoxy/config

	#Restart privoxy
	service privoxy restart

echo -e '\e[35m[+] Installing Routetor \e[0m'

	#Install cuckoo scripts to utilize tor
	cd /opt
	git clone https://github.com/seanthegeek/routetor.git
	cd routetor
	cp *tor* /usr/sbin
	/usr/sbin/routetor &

echo -e '\e[35m[+] Installing Vsftpd \e[0m'

	#Create public accessible folder
	mkdir /home/cuckoo/vmshared/pub
	chown cuckoo:cuckoo /home/cuckoo/vmshared/pub
	chmod 777 /home/cuckoo/vmshared/pub

	#Install vsftpd
	apt-get install vsftpd -y >/dev/null 2>&1

	#Copy vsftpd config file
	cp $cuckoo_path/cuckoo/extra/vsftpd.conf /etc/vsftpd.conf

	#Restart vsftpd
	service vsftpd restart

}

function startup_script
{

echo -e '\e[35m[+] Creating startup script for Cuckoo \e[0m'

	#Install gunicorn
	pip install gunicorn >/dev/null 2>&1

	#Copy default startup script
	cp $cuckoo_path/cuckoo/extra/cuckooboot /usr/sbin/cuckooboot
	chmod +x  /usr/sbin/cuckooboot

	#Modify startup script to fit local environment
	sed -i -e "s@CUCKOO_PATH="/opt/cuckoo"@CUCKOO_PATH="$cuckoo_path"@" /usr/sbin/cuckooboot

	#Add startup crontab entries
	(crontab -l -u cuckoo; echo "46 * * * * /usr/sbin/etupdate")| crontab -u cuckoo -
	(crontab -l -u cuckoo; echo "@reboot /usr/sbin/routetor")| crontab -u cuckoo -
	(crontab -l -u cuckoo; echo "@reboot /usr/sbin/cuckooboot")| crontab -u cuckoo -

	#Run cuckoo
	#/usr/sbin/cuckooboot

echo -e '\e[35m[+] Installation Complete! \e[0m'
}


if [ "$1" = '-h' ]; then
    usage
fi

#check if start with root
if [ $EUID -ne 0 ]; then
	echo 'This script must be run as root'
	exit 1
fi


deps
postgres
machinery
create_cuckoo_user
cuckoo_mod_install
nginx
self_ssl
misc_apps
startup_script

exit 0