#!/bin/bash


echo "Docker installation on RHEL"
source /home/test/.bashrc
				cat /etc/os*
				cd $WORK_DIR
				sudo yum install -y vim iptables-devel.s390x iptables-utils.s390x
				wget https://download.docker.com/linux/static/stable/s390x/docker-18.06.0-ce.tgz
				tar -xvf docker-18.06.0-ce.tgz
				sudo cp docker/* /bin
				ls /bin/ | grep docker
		        	sudo nohup dockerd &
		        	sleep 20s
		        	ps -aef | grep docker
				sudo chmod ugo+rw /var/run/docker.sock
				docker info | grep Version
				sudo free -mh && sudo sync && sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' && sudo free -mh   
        
        echo "Docker installation complete"
