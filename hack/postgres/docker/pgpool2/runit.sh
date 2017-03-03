#!/bin/bash

if [ -f '/srv/pgpool2/secrets/.admin' ]; then
    export $(cat /srv/pgpool2/secrets/.admin | xargs)
else
    echo
    echo 'Missing secerets file /srv/pgpool2/secrets/.admin.'
    echo 'Pass environment variables via rc yaml file.'
    echo
fi
export > /etc/envvars

echo ">>> Adding user $PCP_USER for PCP"
mv /usr/local/etc/pcp.conf.sample      /usr/local/etc/pcp.conf
echo "$PCP_USER:`pg_md5 $PCP_PASSWORD`" >> /usr/local/etc/pcp.conf
echo "*:*:$PCP_USER:$PCP_PASSWORD" > /var/www/.pcppass
chown www-data:www-data /var/www/.pcppass
chmod 600 /var/www/.pcppass


echo ">>> Configure pool_hba.conf"
mv /usr/local/etc/pool_hba.conf.sample /usr/local/etc/pool_hba.conf
{ echo 'host    all         all         10.0.0.0/8            trust'; } >> /usr/local/etc/pool_hba.conf
{ echo 'host    all         all         172.16.0.0/12         trust'; } >> /usr/local/etc/pool_hba.conf
{ echo 'host    all         all         192.168.0.0/16        trust'; } >> /usr/local/etc/pool_hba.conf
{ echo 'host    all         all         0.0.0.0/0             md5'; }   >> /usr/local/etc/pool_hba.conf


CONFIG_FILE='/usr/local/etc/pgpool.conf'

echo ">>> Adding users for md5 auth"
IFS=',' read -ra USER_PASSES <<< "$DB_USERS"
for USER_PASS in ${USER_PASSES[@]}
do
    IFS=':' read -ra USER <<< "$USER_PASS"
    pg_md5 --md5auth --username="${USER[0]}" "${USER[1]}"
done

mkdir -p /var/db/data
# Example:
# 0:database-node1-service:5432:1:/var/lib/postgresql/data:ALLOW_TO_FAILOVER,1:database-node2-service::::,2:database-node3-service::::,3:database-node4-service::::,4:database-node5-service::::
echo ">>> Adding backends"
IFS=',' read -ra HOSTS <<< "$BACKENDS"
for HOST in ${HOSTS[@]}
do
    IFS=':' read -ra INFO <<< "$HOST"

    NUM=""
    HOST=""
    PORT="5432"
    WEIGHT=1
    DIR="/var/db/data"
    FLAG="DISALLOW_TO_FAILOVER"

    [[ "${INFO[0]}" != "" ]] && NUM="${INFO[0]}"
    [[ "${INFO[1]}" != "" ]] && HOST="${INFO[1]}"
    [[ "${INFO[2]}" != "" ]] && PORT="${INFO[2]}"
    [[ "${INFO[3]}" != "" ]] && WEIGHT="${INFO[3]}"
    [[ "${INFO[4]}" != "" ]] && DIR="${INFO[4]}"
    [[ "${INFO[5]}" != "" ]] && FLAG="${INFO[5]}"

    echo "
backend_hostname$NUM = '$HOST'
backend_port$NUM = $PORT
backend_weight$NUM = $WEIGHT
backend_data_directory$NUM = '$DIR'
backend_flag$NUM = '$FLAG'
" >> $CONFIG_FILE

done

echo ">>> Adding user $REPLICATION_USER as check user"
echo "
sr_check_password = '$REPLICATION_PASSWORD'
sr_check_user = '$REPLICATION_USER'" >> $CONFIG_FILE

#CONFIGS= #in format variable1:value1[,variable2:value2[,...]]
#CONFIG_FILE= #path to file


echo "
#------------------------------------------------------------------------------
# AUTOGENERATED
#------------------------------------------------------------------------------
" >> $CONFIG_FILE

echo ">>> Configuring $CONFIG_FILE"
IFS=',' read -ra CONFIG_PAIRS <<< "$CONFIGS"
for CONFIG_PAIR in ${CONFIG_PAIRS[@]}
do
    IFS=':' read -ra CONFIG <<< "$CONFIG_PAIR"
    VAR="${CONFIG[0]}"
    VAL="${CONFIG[1]}"
    sed -e "s/\(^\ *$VAR\(.*\)$\)/#\1 # overrided in AUTOGENERATED section/g" $CONFIG_FILE > /tmp/config.tmp && mv -f /tmp/config.tmp $CONFIG_FILE
    echo ">>>>>> Adding config '$VAR' with value '$VAL' "
    echo "$VAR = $VAL" >> $CONFIG_FILE
done
echo ">>>>>> Result config file"
#cat $CONFIG_FILE

chmod -R 644 /usr/local/etc/*.conf

echo "Starting runit..."
exec /usr/sbin/runsvdir-start