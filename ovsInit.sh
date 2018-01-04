#!/bin/bash
#Start OVS in the Contiv container

set -euo pipefail

if ! lsmod | cut -d" " -f1 | grep -q openvswitch; then
    echo "INFO: Loading kernel module: openvswitch"
    modprobe openvswitch
    sleep 2
fi

mkdir -p /var/run/openvswitch /var/log/contiv

if [ -d "/etc/openvswitch" ]; then
    if [ -f "/etc/openvswitch/conf.db" ]; then
        echo "INFO: The Open vSwitch database exists"
    else
        echo "INFO: The Open VSwitch database doesn't exist"
        echo "INFO: Creating the Open VSwitch database..."
        ovsdb-tool create /etc/openvswitch/conf.db /usr/share/openvswitch/vswitch.ovsschema
    fi
else
    echo "CRITICAL: Open vSwitch is not mounted from host"
    exit 1
fi

echo "INFO: Starting ovsdb-server..."
ovsdb-server --remote=punix:/var/run/openvswitch/db.sock \
    --remote=db:Open_vSwitch,Open_vSwitch,manager_options \
    --private-key=db:Open_vSwitch,SSL,private_key \
    --certificate=db:Open_vSwitch,SSL,certificate \
    --bootstrap-ca-cert=db:Open_vSwitch,SSL,ca_cert \
    --log-file=/var/log/contiv/ovs-db.log -vsyslog:info -vfile:info \
    --pidfile /etc/openvswitch/conf.db &
OVSDB_PID=$!

echo "INFO: Starting ovs-vswitchd"
ovs-vswitchd -v --pidfile --detach --log-file=/var/log/contiv/ovs-vswitchd.log \
    -vconsole:err -vsyslog:info -vfile:info &
VSWITCHD_PID=$!

retry=0
while ! ovsdb-client list-dbs | grep -q Open_vSwitch; do
    if [[ ${retry} -eq 5 ]]; then
        echo "CRITICAL: Failed to start ovsdb in 5 seconds."
        exit 1
    else
        echo "INFO: Waiting for ovsdb to start..."
        sleep 1
        ((retry += 1))
    fi
done

echo "INFO: Setting OVS manager (tcp)..."
ovs-vsctl set-manager tcp:127.0.0.1:6640

echo "INFO: Setting OVS manager (ptcp)..."
ovs-vsctl set-manager ptcp:6640

STATUS=0

for pid in $OVSDB_PID $VSWITCHD_PID; do
    echo "INFO: waiting for pid $pid"
    wait $pid || let STATUS=1
done

exit $STATUS
