#!/bin/sh

set -e

if [ `id -u` != 0 ]; then
    echo "Install script can only be ran as root"
    exit 1
fi

create_link() {
    rm -f $2
    ln -s $1 $2
    chmod a+x $1
    chmod a+x $2
}

install() {
    local DESTINATION=$1

    if [ -d $DESTINATION ]; then
        echo "Kubernetes manager is already installed. Make sure you save the"
        echo "necessary configuration files and run \`rm -rf $DESTINATION\`"
        exit 0
    fi

    rm -rf $DESTINATION 
    git clone https://github.com/wiilog/kubernetes-manager.git $DESTINATION > /dev/null 2> /dev/null
    create_link $DESTINATION/manager.sh    /bin/kmn
    create_link $DESTINATION/manager.sh    /bin/kman
    create_link $DESTINATION/cron.sh       /bin/kron

    echo "Successfully installed Kubernetes Manager, you can use it by running \`kmn\` or \`kman\`"
}

install /opt/kubernetes-manager