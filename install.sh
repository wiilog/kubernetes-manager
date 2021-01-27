#!/bin/bash

USER=$SUDO_USER
HOME=$(eval echo ~$SUDO_USER)

set -e

if [ `id -u` != 0 ]; then
    echo "Install script can only be ran as root"
    exit 1
fi

if [ ! -f $HOME/.kube/config ]; then
    echo "No kube config found, please place your kubeconfig in $HOME/.kube/config"
    exit 2
fi

function create_link() {
    rm -f $2
    ln -s $1 $2
    chmod a+x $1
}

function prepare_permissions() {
    groupadd kmn -f
    groupadd docker -f
    adduser $USER kmn -q
    adduser $USER docker -q
}

function install_dependencies() {
    echo
    echo
    echo "    Installing dependencies"
    echo
    echo

    apt-get update
    apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common --yes
    
    # Docker
    curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"

    # Helm
    curl https://baltocdn.com/helm/signing.asc | apt-key add -
    echo "deb https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list
    
    # Install Docker and Helm
    apt-get update --yes
    apt-get install git docker-ce docker-ce-cli containerd.io helm --yes

    # Kubectl
    curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.18.8/bin/linux/amd64/kubectl
    chmod +x ./kubectl
    sudo mv ./kubectl /usr/local/bin/kubectl
}

function initialize_docker() {
    echo
    echo
    echo "    Initializing Docker"
    echo
    echo

    docker login

    chown -R $USER:$USER $HOME/.docker
}

function install_kmn() {
    git clone https://github.com/wiilog/kubernetes-manager.git $DESTINATION > /dev/null 2> /dev/null
    create_link $DESTINATION/manager.sh    /bin/kmn
    create_link $DESTINATION/manager.sh    /bin/kman
    create_link $DESTINATION/cron.sh       /bin/kron

    chgrp -R kmn $DESTINATION
    chmod -R 770 $DESTINATION
}

function install() {
    local DESTINATION=$1

    if [ -d $DESTINATION ]; then
        echo "Kubernetes manager is already installed. Make sure you save the"
        echo "necessary configuration files and run \`rm -rf $DESTINATION\`"
        exit 0
    fi

    prepare_permissions
    install_dependencies
    initialize_docker
    install_kmn

    echo
    echo
    echo "Successfully installed Kubernetes Manager, you can use it by running \`kmn\` or \`kman\`"
    echo "$(tput bold)You must relog before continuing$(tput sgr0)"
}

install /opt/kubernetes-manager
rm "${BASH_SOURCE[0]}"