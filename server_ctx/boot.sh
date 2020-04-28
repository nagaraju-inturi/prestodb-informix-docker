#!/bin/sh 

export INFORMIXDIR=/opt/ibm/informix
export PATH=":${INFORMIXDIR}/bin:.:${PATH}"
#export INFORMIXSERVER=informix
export INFORMIXSQLHOSTS="${INFORMIXDIR}/etc/sqlhosts"
export ONCONFIG=onconfig
export LD_LIBRARY_PATH="${INFORMIXDIR}/lib:${INFORMIXDIR}/lib/esql:${LD_LIBRARY_PATH}"
export DATA_ROOT="${DATA_ROOT:-/opt/ibm/data/}"

SLEEP_TIME=1  # Seconds
MAX_SLEEP=240 # Seconds

echoThis()
{
  timestamp=`date --rfc-3339=seconds`
  echo "[$timestamp] $@"
  echo "[$timestamp] $@" >> /tmp/informix.log
}

function clean_up {

    # Perform program exit housekeeping
    echo "${sn} stop: Shutting down informix Instance ..."
    su informix -c "${INFORMIXDIR}/bin/onmode -kuy"
    echo "${sn} stop: done"
    
    exit 0
}

trap clean_up SIGHUP SIGINT SIGTERM


if [ -f /etc/profile.d/informix.sh ]; then
    . /etc/profile.d/informix.sh
fi
local_ip=`ifconfig eth0 |awk '{if(NR==2)print $2}'`

preStart()
{
setStr="
#!/bin/bash

export GOROOT=/usr/local/go
export GOPATH=/opt/ibm/godb/
export PATH=${GOPATH}/bin:${GOROOT}/bin:${PATH}
export ODBCINI=/etc/odbc.ini
export INFORMIXDIR=/opt/ibm/informix
export PATH="${INFORMIXDIR}/bin:\${PATH}"
export INFORMIXSERVER=informix
export HA_ALIAS=\"${HA_ALIAS}\"
export INFORMIXSQLHOSTS=\"${INFORMIXSQLHOSTS}\"
export ONCONFIG=\"onconfig\"
export LD_LIBRARY_PATH="${INFORMIXDIR}/lib:${INFORMIXDIR}/lib/esql:${LD_LIBRARY_PATH}"
"
   echo "${setStr}" > /etc/profile.d/informix.sh
   . /etc/profile.d/informix.sh
   chown informix:informix /etc/profile.d/informix.sh
   chmod 644 /etc/profile.d/informix.sh
   echo "informix onsoctcp $local_ip 60000 " >${INFORMIXDIR}/etc/sqlhosts

   chown informix:informix ${INFORMIXDIR}/etc/sqlhosts
   sed -i "s/DBSERVERNAME.*/DBSERVERNAME informix /g" ${INFORMIXDIR}/etc/$ONCONFIG
   sed -i "s/ROOTPATH.*/ROOTPATH \/opt\/ibm\/data\/dbspaces\/rootdbs /g" ${INFORMIXDIR}/etc/onconfig
   sed -i "s/MSGPATH.*/MSGPATH \/opt\/ibm\/data\/log\/$HA_ALIAS.log /g" ${INFORMIXDIR}/etc/onconfig
   sed -i "s/FULL_DISK_INIT.*/FULL_DISK_INIT 1 /g" ${INFORMIXDIR}/etc/onconfig
   sed -i "s/LOG_INDEX_BUILDS.*/LOG_INDEX_BUILDS 1 /g" ${INFORMIXDIR}/etc/onconfig
   sed -i "s/TEMPTAB_NOLOG.*/TEMPTAB_NOLOG 1 /g" ${INFORMIXDIR}/etc/onconfig
   sed -i "s/ENABLE_SNAPSHOT_COPY.*/ENABLE_SNAPSHOT_COPY 1 /g" ${INFORMIXDIR}/etc/onconfig
   sed -i "s/CDR_QUEUEMEM.*/CDR_QUEUEMEM 200000 /g" ${INFORMIXDIR}/etc/onconfig
   sed -i "s/CDR_QDATA_SBSPACE.*/CDR_QDATA_SBSPACE ersbsp /g" ${INFORMIXDIR}/etc/onconfig
   sed -i "s/LTAPEDEV.*/LTAPEDEV \/dev\/null /g" /opt/ibm/informix//etc/onconfig
   sed -i "s/VPCLASS cpu/VPCLASS cpu=2/g" ${INFORMIXDIR}/etc/onconfig
   sed -i "s/CDR_SUPPRESS_ATSRISWARN.*/CDR_SUPPRESS_ATSRISWARN 2,3,4/g" ${INFORMIXDIR}/etc/$ONCONFIG
   sed -i "s/JVPCLASSPATH.*/JVPCLASSPATH \$INFORMIXDIR\/extend\/krakatoa\/krakatoa\.jar:\$INFORMIXDIR\/jars\/org\.eclipse\.paho\.client\.mqttv3-1.2.0\.jar/g" ${INFORMIXDIR}/etc/onconfig
   echo "VPCLASS jvp,num=1" >> ${INFORMIXDIR}/etc/onconfig

   chown informix:informix ${INFORMIXDIR}/etc/onconfig
   mkdir -p ${DATA_ROOT}/dbspaces
   touch ${DATA_ROOT}/dbspaces/rootdbs
   touch ${DATA_ROOT}/dbspaces/ersbsp
   chown -R informix:informix ${DATA_ROOT}
   chmod 660 ${DATA_ROOT}/dbspaces/rootdbs
   chmod 660 ${DATA_ROOT}/dbspaces/ersbsp
   su informix -c "mkdir -p ${DATA_ROOT}/log"
   su informix -c "touch ${DATA_ROOT}/log/$HA_ALIAS.log"
   su informix -c "mkdir ${INFORMIXDIR}/jars"
}

# Wait for local server to be On-Line.
wait4online()
{
retry=0
wait4online_status=0
while [ 1 ]
    do
    sleep 10
    onstat -
    server_state=$?

    #Offline mode
    if [ $server_state -eq 255 ]
    then
        wait4online_status=1
        printf "ERROR: wait4online() Server is in Offline mode\n" 
        break
    fi

    # Quiescent mode check.
    # Note: at secondary server, exit code 2 used for Quiscent mode as well.
    if [ $server_state -eq 1 ] || [ $server_state -eq 2 ]
    then
        su -p informix -c 'onmode -m; exit $?'
        onmode_rc=$?
        printf "CMD: onmode -m, exit code $onmode_rc \n" 
        if [  $server_state -ne 2 ]
        then
            printf "INFO: wait4online() Server state changed from Quiescent to On-Line mode\n" 
        fi
    fi
    #Check if sqlexec connectivity is enabled or not.
    onstat -g ntd|grep sqlexec|grep yes
    exit_status=$?
    if [ $exit_status -eq 0 ]
    then
        su informix -c "${INFORMIXDIR}/bin/dbaccess sysadmin - <<EOF
EOF"
        rc=$?
        if [ $? -eq 0 ]
        then
           wait4online_status=0
           break
        fi
    fi
    sleep 1
    retry=$(expr $retry + 1)
    if [ $retry -eq 120 ]
    then
       wait4online_status=1
       printf "ERROR: wait4online() Timed-out waiting for server to allow client connections\n" 
       break
    fi
done
}


echo $1
case "$1" in
    '--start')
        if [ `${INFORMIXDIR}/bin/onstat 2>&- | grep -c On-Line` -ne 1 ]; then
            if [ ! -f ${DATA_ROOT}/dbspaces/rootdbs ]; then
               HA_ALIAS=informix
               preStart
               su informix -c "oninit -ivy" 
	       sleep 30
               wait4online
	       sleep 5
               su informix -c "${INFORMIXDIR}/bin/dbaccess sysadmin - <<EOF
               EXECUTE FUNCTION task(\"storagepool add\",\"${DATA_ROOT}/dbspaces/\",\"0\", \"0\", \"32768\",\"1\");
EOF"

               git clone https://github.com/nagaraju-inturi/presto-with-informix.git
               cd presto-with-informix
                ./mvnw clean install -DskipTests
               cp presto-server/target/presto-server-0.235-SNAPSHOT.tar.gz ../
               cd ..
               gunzip presto-server-0.235-SNAPSHOT.tar.gz
               tar -xvf presto-server-0.235-SNAPSHOT.tar
               cd presto-server-0.235-SNAPSHOT
               wget http://media.sundog-soft.com/hadoop/presto-hdp-config.tgz
               tar -xvzf presto-hdp-config.tgz
               cp /opt/ibm/presto-with-informix/presto-main/etc/catalog/informix.properties etc/catalog/
               cp /opt/ibm/presto-with-informix/presto-main/etc/catalog/mysql.properties etc/catalog/
               cp /opt/ibm/presto-with-informix/presto-main/etc/catalog/postgresql.properties etc/catalog/
               sed -i "s/connection-url.*/connection-url=jdbc:postgresql:\/\/127.0.0.1:5432\/template1/g" etc/catalog/postgresql.properties
               sed -i "s/connection-user.*/connection-user=postgres/g" etc/catalog/postgresql.properties
               sed -i "s/connection-password.*/connection-password=changeme/g" etc/catalog/postgresql.properties
               wget https://repo1.maven.org/maven2/com/facebook/presto/presto-cli/0.234.1/presto-cli-0.234.1-executable.jar
               mv presto-cli-0.234.1-executable.jar bin/presto
               chmod +x bin/presto
               
               cd /opt/ibm/
               mkdir /run/systemd/system
               /usr/lib/systemd/systemd --system &
               sleep 5
               # https://linuxize.com/post/how-to-install-postgresql-on-centos-7/
               postgresql-setup initdb
               sed -i "s/ident/trust/g" /var/lib/pgsql/data/pg_hba.conf
               systemctl start postgresql
               systemctl enable postgresql
 
               wget https://dev.mysql.com/get/mysql80-community-release-el7-1.noarch.rpm
               rpm -Uvh mysql80-community-release-el7-1.noarch.rpm
               yum install -y mysql-server
               systemctl start mysqld &
               systemctl status mysqld
               sleep 30
               temp_password=$(grep 'temporary password' /var/log/mysqld.log | awk '{print $NF}')
               # Set up a batch file with the SQL commands
               echo "ALTER USER 'root'@'localhost' IDENTIFIED BY 'Changeme4@'; flush privileges;" > reset_pass.sql

               # Log in to the server with the temporary password, and pass the SQL file to it.
               mysql -u root --password="$temp_password" --connect-expired-password < reset_pass.sql

               cd /opt/ibm/presto-server-0.235-SNAPSHOT
               sed -i "s/connection-url.*/connection-url=jdbc:mysql:\/\/127.0.0.1:3306/g" etc/catalog/mysql.properties
               sed -i "s/connection-password.*/connection-password=Changeme4@/g" etc/catalog/mysql.properties
               cd /opt/ibm/
               echo "postgres:changeme"|chpasswd
               su postgres -c "psql template1 -f pg.sql"
               mysql -u root --password=Changeme4@ < mysql.sql
               su informix -c "dbaccess - ifmx.sql"
               

               /opt/ibm/presto-server-0.235-SNAPSHOT/bin/launcher start
               cd /opt/ibm/
               onstat -m
               su informix -c "onspaces -c -S ersbsp -Df "AVG_LO_SIZE=2,LOGGING=ON" -p  ${DATA_ROOT}/dbspaces/ersbsp -s 500000 -o 0"
               tail -f  ${DATA_ROOT}/log/$HA_ALIAS.log
            else
                echo "${sn} start: Starting informix Instance ..."
                su informix -c "${INFORMIXDIR}/bin/oninit -vy" && tail -f  ${DATA_ROOT}/log/$HA_ALIAS.log
            fi
            echo "${sn} start: done"
            /bin/bash
        fi
        ;;
    '--stop')
        if [ `$INFORMIXDIR/bin/onstat 2>&- | grep -c On-Line` -eq 1 ]; then
            echo "${sn} stop: Shutting down informix Instance ..."
            su informix -c "${INFORMIXDIR}/bin/onmode -kuy"
            echo "${sn} stop: done"
        fi
        ;;

    '--status')
        s="down"
        if [ `${INFORMIXDIR}/bin/onstat 2>&- | grep -c On-Line` -eq 1 ]; then
            s="up"
        fi
        echo "${sn} status: informix Instance is ${s}"
        ;;

    '--shell')
        /bin/bash -c "$2 $3 $4 $5 $6"
        ;;
    *)
        echo "Usage: ${sn} {--start|--stop|--status}"
        ;;
esac

exit 0
