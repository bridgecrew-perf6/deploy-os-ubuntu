#!/bin/bash
#
# Variables editable
MASTERIP=${MASTERIP:-172.20.52.109}
MOUNTPOINT=${MOUNTPOINT:-/opt/data}
JUPYHOME=${MOUNTPOINT}/jupyterlab
CONFUSER=${CONFUSER:-$USER}
UBUNHOME=${MOUNTPOINT}/${CONFUSER}_home
HOMEU=${HOMEU:-/home/$CONFUSER}
#
# Variables must not be changed
CURRENTIP=$(ip a | grep inet.172 | awk '{print $2}' | awk -F'/' '{print $1}')
#
#
if [ "$MASTERIP" = "$CURRENTIP" ]; then
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

conf_jupyter(){
if [ -d $MOUNTPOINT ]; then
   mkdir -p $JUPYHOME $UBUNHOME 2>/dev/null
   # configuring jupyter user home directory
   chown root:jupyterhub-users $JUPYHOME
   chmod 1777 $JUPYHOME

   # move dirs on jupteradmin
   for user in jupyter-jupyadmin ubuntu; do
     echo "-- Moving dirs for [$user]"
     case $user in
        "jupyter-jupyadmin")
        export OPTHOME="$JUPYHOME/$user"
        ;;
        "ubuntu")
        export OPTHOME=$UBUNHOME
        ;;
     esac
     mkdir -p $OPTHOME 2>/dev/null
     chown $user:$user ${OPTHOME}
     ( cd /home/$user ;
       for dir in .local .cache .conda; do
         mkdir -p ${OPTHOME}/$dir;
	 if [ ! -h $dir -a -d $dir ]; then
            rm -rf ${OPTHOME}/$dir
            mv -fv $dir $OPTHOME/
         fi
         ln -fs ${OPTHOME}/$dir;
       done
     ) 2>/dev/null
   done

   # update jupyterlab workdir
   rsync -auq /opt/jupyterlab_workdir/ $JUPYHOME/ 2>/dev/null

   # tljh optimization
   # nativeauthenticator.NativeAuthenticator
   JUPYCONFIG=/opt/tljh/config/jupyterhub_config.d/jupyterhub_config.py
   if [[ ! `grep ^c.Spawner.notebook_dir $JUPYCONFIG 2>/dev/null ]]; then
      echo "c.Spawner.notebook_dir='$JUPYHOME'" >> $JUPYCONFIG
   fi
   tljh-config set limits.memory $(head -1 /proc/meminfo | awk '{print $2*0.85"K"}')
   tljh-config set limits.cpu $(echo "`nproc` * 0.8" | bc | awk '{print int($0) }')
   tljh-config set user_environment.default_app jupyterlab
   tljh-config unset auth.type 
   tljh-config reload
   tljh-config show
else
   init
fi
}

#
# input $1 : device path ex. /dev/sdb
#
do_format(){
  FINDDEV=$(dmesg | grep -i sdb: | awk -F': ' '{print "/dev/"$2}' | awk '{print $1}' | tr -d '[0-9]')
  INDEV=${1:-$FINDDEV}
  DEV=${INDEV:-/dev/sdb}
  echo -n "** Read to destroy data in [$DEV] (y/N)? "; read ANS
  [ "$ANS" != "y" ] && return 1
  umount $MOUNTPOINT 2>/dev/null
  parted $DEV mklabel gpt && parted $DEV mkpart primary ext4 0% 100% && {
  parted $DEV print && mkfs.ext4 -F ${DEV}1 || exit 1
  mkdir -p $MOUNTPOINT 2>/dev/null
  if [ -z "`grep ^$DEV /etc/fstab 2>/dev/null`" ]; then
     echo '${DEV} $MOUNTPOINT ext4 defaults 0 0' >> /etc/fstab
  fi
  }
  mount -a
}

conf_docker(){
if [ -d $MOUNTPOINT ]; then 
   mkdir -p $MOUNTPOINT/docker 2>/dev/null
   if [ ! -h /var/lib/docker -a -d /var/lib/docker ]; then
      if [ -d $MOUNTPOINT/docker ]; then
	 rsync -auq --delete /var/lib/docker/ $MOUNTPOINT/docker/ 2>/dev/null
	 rm -rf /var/lib/docker 2>/dev/null
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
# do_format [/dev/sdb]
# conf_jupyter
# conf_docker
#
cat<<EOF
--------------------------------------------
-- Editable variables ----------------------
CONFUSER=$CONFUSER
MASTERIP=$MASTERIP
MOUNTPOINT=$MOUNTPOINT
JUPYHOME=$JUPYHOME
UBUNHOME=$UBUNHOME
HOMEU=$HOMEU
--------------------------------------------
EOF
$@
exit 0
