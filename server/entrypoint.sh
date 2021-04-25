#!/bin/bash

CLIENTCERTPATH='/etc/openvpn/'${CLIENTCERTNAME}'.ovpn'
EASYRSA='/usr/share/easy-rsa'
BASEDIR='/etc/openvpn/data'
SERVERCONF=${BASEDIR}'/server.conf'
INITFLAG=${BASEDIR}'/.initflag'
CLIENTDIR=${BASEDIR}'/cert/client/'${CLIENTCERTNAME}
SERVERDIR=${BASEDIR}'/cert/server'
SERVERCERTNAME=${RANDOM}
DEVICE='eth0'

function generateCert(){
    mkdir -p ${SERVERDIR}
    mkdir -p ${CLIENTDIR}
    cd $EASYRSA
    ./easyrsa init-pki
    ./easyrsa --batch build-ca nopass
    echo '######################################################'
    echo '#      Start to generate diffie hellman key          #'
    echo '######################################################'
    ./easyrsa gen-dh
    openvpn --genkey --secret ${EASYRSA}/pki/ta.key
    ./easyrsa build-server-full ${SERVERCERTNAME} nopass
    ./easyrsa build-client-full ${CLIENTCERTNAME} nopass
    mv ${EASYRSA}/pki/ca.crt ${SERVERDIR}
    mv ${EASYRSA}/pki/issued/${SERVERCERTNAME}.crt ${SERVERDIR}
    mv ${EASYRSA}/pki/private/${SERVERCERTNAME}.key ${SERVERDIR}
    mv ${EASYRSA}/pki/ta.key ${SERVERDIR}
    mv ${EASYRSA}/pki/dh.pem ${SERVERDIR}
    mv ${EASYRSA}/pki/issued/${CLIENTCERTNAME}.crt ${CLIENTDIR}
    mv ${EASYRSA}/pki/private/${CLIENTCERTNAME}.key ${CLIENTDIR}
    echo '#######################################################'
    echo '#  Finish to generate certification. please download. #'
    echo '#######################################################'
}

function convertNetmask(){
    local network=${1}
    local index=0
    RESULT=''

    for x in ${network//// }; do
        [[ $index -eq 0 ]] && { RESULT=$x' '; }
        [[ $index -eq 1 ]] && { SUBNET=$x; }
        ((index++))
    done
    local subnetmask=''
    for((i=0; i < $((SUBNET / 8)); i++)); do
        subnetmask+='255.'
    done
    subnetmask+=$((256 - ( 1 << (8 - (SUBNET % 8)))))
    for((i=0; i < $((3 - (SUBNET / 8))); i++)); do
        subnetmask=${subnetmask}'.0'
    done
    RESULT+=$subnetmask
}

function createClientCert(){
    cat <<EOF > $CLIENTCERTPATH
client
dev tun
proto udp
remote $PUBLICIP $EXTERNALPORT
resolv-retry infinite
nobind
persist-key
persist-tun
user nobody
group nobody
remote-cert-tls server
tls-client
comp-lzo
cipher AES-256-CBC
verb 4
tun-mtu 1500
key-direction 1
EOF

    echo '<ca>' >> $CLIENTCERTPATH
    cat ${SERVERDIR}/ca.crt >> $CLIENTCERTPATH
    echo '</ca>' >> $CLIENTCERTPATH

    echo '<key>' >> $CLIENTCERTPATH
    cat ${CLIENTDIR}/${CLIENTCERTNAME}.key >> $CLIENTCERTPATH
    echo '</key>' >> $CLIENTCERTPATH

    echo '<cert>' >> $CLIENTCERTPATH
    cat ${CLIENTDIR}/${CLIENTCERTNAME}.crt >> $CLIENTCERTPATH
    echo '</cert>' >> $CLIENTCERTPATH

    echo '<tls-auth>' >> $CLIENTCERTPATH
    cat ${SERVERDIR}/ta.key >> $CLIENTCERTPATH
    echo '</tls-auth>' >> $CLIENTCERTPATH
}

function downloadPem(){
    python3 /etc/openvpn/pem.py $CLIENTCERTPATH $INTERNALPORT
}

function serverConfig(){
    cat <<EOF > $SERVERCONF
port ${INTERNALPORT}
proto udp
dev tun
ca ${SERVERDIR}/ca.crt
cert ${SERVERDIR}/${SERVERCERTNAME}.crt
key ${SERVERDIR}/${SERVERCERTNAME}.key
dh ${SERVERDIR}/dh.pem
keepalive 10 120
tls-auth ${SERVERDIR}/ta.key 0
cipher AES-256-CBC
comp-lzo
max-clients 1
user nobody
group nobody
persist-key
persist-tun
status /var/log/openvpn-status.log
log         /var/log/openvpn.log
log-append  /var/log/openvpn.log
verb 4
explicit-exit-notify 1
EOF
    convertNetmask $TUNNELNETWORK
    echo 'server '${RESULT} >> $SERVERCONF
    env | grep -E 'ROUTING[[:digit:]]' | while read line; do
        local index=0
        for part in ${line//=/ }; do
            if [ $index -eq 1 ]; then
                convertNetmask $part
                echo 'push "route '${RESULT}'"' >> $SERVERCONF
            fi
            ((index++))
        done
    done
}

function startVPN(){
    mkdir /dev/net
    mknod /dev/net/tun c 10 200
    echo $TUNNELNETWORK
    echo $DEVICE
    iptables -t nat -A POSTROUTING -s $TUNNELNETWORK -o $DEVICE -j MASQUERADE
    env | grep -E 'ROUTING[[:digit:]]' | while read line; do
        local index=0
        for part in ${line//=/ }; do
            if [ $index -eq 1 ]; then
                echo $part
                iptables -t nat -A POSTROUTING -s $part -o $DEVICE -j MASQUERADE
                break
            fi
            ((index++))
        done
    done
    exec openvpn --config ${SERVERCONF}
}

function addRouting(){
    BridgeIP=`host openvpn-bridge | awk '{print $4}'`
    ip route add $BRIDGENETWORK via $BridgeIP
}

function main(){
    sleep 1
    if [[ ! -e $INITFLAG ]]; then
        touch $INITFLAG
        generateCert
        serverConfig
        createClientCert
        downloadPem
        addRouting
    else
        echo 'Installation of OpenVPN already done.'
    fi
    startVPN
    if [ $? -eq 0 ]; then
        echo 'Starting OpenVPN process has been sucessed.'
    else
        echo 'Starting OpenVPN process has been failed.'
    fi
}

main
