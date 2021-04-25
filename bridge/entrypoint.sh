#!/bin/bash

BASEDIR='/etc/openvpn/client'

OVPNFILE=`ls $BASEDIR`

mkdir /dev/net
mknod /dev/net/tun c 10 200

iptables -A FORWARD -i tun0 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o tun0 -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE

openvpn --config ${BASEDIR}/${OVPNFILE}
