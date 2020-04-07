#!/bin/bash

echo "Docker installation on Ubuntu"
sudo apt-get update
				cat /etc/os*
				if [ -f "/etc/os-release" ]; then
				       source "/etc/os-release"
				fi
				DISTRO="$ID-$VERSION_ID"
				echo $DISTRO
				if [[ "$DISTRO" == "ubuntu-19.10"  ]]; then
				    echo "Inside Ubuntu 19.10"
				    sudo apt-get update
					sudo apt install -y wget tar iptables patch libdevmapper-dev 
					wget https://download.docker.com/linux/static/stable/s390x/docker-18.06.0-ce.tgz
					tar -xvf docker-18.06.0-ce.tgz
					sudo cp docker/* /bin
					ls /bin/ | grep docker
					sudo nohup dockerd &
					sleep 20s
					ps -aef | grep dockerd
					sudo sudo chmod ugo+rw /var/run/docker.sock
					docker info | grep Version	
					docker ps
					sudo free -mh && sudo sync && sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' && sudo free -mh
				
				else
					echo "Inside Ubuntu 16.04/18.04"
					sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apt-transport-https  ca-certificates  curl software-properties-common
					curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
					sudo add-apt-repository "deb [arch=s390x] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
					sudo apt-get update
					sudo apt-get install -y docker-ce
					sudo service docker start
					sleep 60s	
                    sudo sudo chmod ugo+rw /var/run/docker.sock
					sudo service docker status
					docker version	
                    docker ps
                    sudo free -mh && sudo sync && sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' && sudo free -mh
				fi  

        echo "Docker installation complete"
