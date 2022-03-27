#!/bin/bash
#
# Variables editable
MASTERIP=${MASTERIP:-172.20.52.109}
MOUNTPOINT=${MOUNTPOINT:-/opt/data}
JUPYHOME=${MOUNTPOINT}/jupyterlab
UBUNHOME=${MOUNTPOINT}/ubuntu_home
HOMEU=${HOMEU:-/home/$USER}
#
# Variables must not be changed
CURRENTIP=$(ip a | grep inet.172 | awk '{print $2}' | awk -F'/' '{print $1}')
#
#
if [ "$MASTERIP" != "$CURRENTIP" ]; then
   echo "** nothing will be done on the master **"
   exit 1
fi
if [ `id -u` -ne 0 ]; then
   echo "** please run as root **"
   exit 1
fi

init(){
   echo -n "-- creating [$MOUNTPOINT] "
   mkdir -p $MOUNTPOINT 2>/dev/null && echo ..ok || echo "**nok (exists already or issue)"
}

jupyter(){
mkdir -p $JUPYHOME $UBUNHOME 2>/dev/null
if [ -d $MOUNTPOINT ]; then
   # configuring jupyter user home directory
   chown root:jupyterhub-users $JUPYHOME
   chmod 1777 $JUPYHOME

   # move .local
   chown ubuntu:ubuntu $UBUNHOME
   chmod 0754 $UBUNHOME
   if [ ! -h $HOMEU/.local ]; then
      if [ ! -d $UBUNHOME/.local ]; then  
         ( cd $HOMEU && mv -v $HOMEU/.local $UBUNHOME/ )
      fi
      ( cd $HOMEU && ln -fs $UBUNHOME/.local )
   fi

   # tljh optimization
   tljh-config set limits.memory $(head -1 /proc/meminfo | awk '{print $2*0.85"K"}')
   tljh-config set limits.cpu $(echo "`nproc` * 0.8" | bc | awk '{print int($0) }')
   tljh-config set user_environment.default_app jupyterlab
   tljh-config set auth.type nativeauthenticator.NativeAuthenticator
   tljh-config reload
else
   init
fi
}

#
# input $1 : device path ex. /dev/sdb
#
format(){
  FINDDEV=$(dmesg | grep -i sdb: | awk -F': ' '{print "/dev/"$2}' | awk '{print $1}')
  INDEV=${1:-$FINDDEV}
  DEV=${INDEV:-/dev/sdb}
  parted $DEV mklabel gpt && parted $DEV mkpart primary ext4 0% 100% && {
  parted $DEV print && mkfs.ext4 -F ${DEV}1 || exit 1
  mkdir -p $MOUNTPOINT 2>/dev/null
  if [ -z "`grep $DEV /etc/fstab 2>/dev/null`" ]; then
     echo '${DEV} $MOUNTPOINT ext4 defaults 0 0' >> /etc/fstab
  fi
  }
  mount -a
}

docker(){
if [ -d $MOUNTPOINT ]; then
   if [ ! -h /var/lib/docker -a -d /var/lib/docker ]; then
      if [ -d $MOUNTPOINT/docker ]; then
	 rsync -auq --delete /var/lib/docker/ $MOUNTPOINT/docker/ 2>/dev/null
	 rm -f /var/lib/docker 2>/dev/null
      else
	 mv -f /var/lib/docker $MOUNTPOINT/ 2>/dev/null
      fi
   fi
   ln -fs $MOUNTPOINT/docker 2>/dev/null
   systemctl restart docker
   docker info 2>/dev/null | grep "Root Dir:"
else
   init
fi
}

#
# init
# format [/dev/sdb]
# jupyter
# docker
#
cat<<EOF
--------------------------------------------
-- Editable variables ----------------------
MASTERIP=$MASTERIP
MOUNTPOINT=$MOUNTPOINT
JUPYHOME=$JUPYHOME
UBUNHOME=$UBUNHOME
HOMEU=$HOMEU
--------------------------------------------
EOF
for i in "$@"; do
   echo $i
done
exit 0
