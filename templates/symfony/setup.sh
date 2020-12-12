#!/bin/bash

NAME=$1

if [ -f ../../configs/passwords/$NAME ]; then
    DATABASE_PASSWORD=$(cat ../../configs/passwords/$NAME)
else
    DATABASE_PASSWORD=$(openssl rand -base64 16 | tr --delete =/+)

    # Make sure the password contains uppercase
    while [[ -z $(echo $DATABASE_PASSWORD | awk "/[a-z]/ && /[A-Z]/ && /[0-9]/") ]]; do
        DATABASE_PASSWORD=$(openssl rand -base64 16 | tr --delete =/+)
    done

    echo $DATABASE_PASSWORD > ../../configs/passwords/$NAME
fi

declare -A DATABASE
DATABASE[host]=cb249510-001.dbaas.ovh.net
DATABASE[port]=35403
DATABASE[user]=$NAME
DATABASE[pass]=$DATABASE_PASSWORD

declare -a NAMES
declare -a VALUES

function wiistock() {
    kubectl --namespace=wiistock "$@"
}

function create_directories() {
    local NAME=$1

    if [ -d ../../configs/$NAME ]; then
        read -p "Instance \"$NAME\" already exists data may get corrupted, continue? " REPLY

        if [[ ! $REPLY =~ ^[Yy1]$ ]]; then
            exit 0
        fi
    fi

    mkdir -p ../../configs/$NAME
}

function request_configuration() {
    echo ""
    echo "  Configuration"
    read -p "Replicas count:   " REPLICAS_COUNT
    read -p "Base domain name: " DOMAIN
    read -p "Repository:       " REPOSITORY
    read -p "Branch:           " BRANCH
    echo ""

    for NUMBER in {1..5}; do
        echo "Variable $NUMBER (leave empty to stop)"
        read -p "Name:  " EXTRA_NAME
        if [ -z $EXTRA_NAME ]; then
            echo ""
            break
        fi

        read -p "Value: " EXTRA_VALUE
        echo ""

        NAMES[$NUMBER]=$EXTRA_NAME
        VALUES[$NUMBER]=$EXTRA_VALUE
    done
}

function request_database_creation() {
    local NAME=$1

    echo "Create the following user with administrator rights on the database"
    echo "on OVH panel and press enter when OVH is done creating everything"
    echo -e "    User      \"$NAME\"\tidentified by password\t${DATABASE[pass]}"
    echo -e "    Database  \"$NAME\""

    read
}

function request_domains_creation() {
    local NAME=$1
    local DOMAIN=$2
    local IP=$(kubectl get service ingress-nginx-controller --namespace=ingress-nginx --no-headers | tr -s ' ' | cut -d ' ' -f 4)

    shift 2

    echo ""
    echo "Create the following domain and press enter when done"
    echo -e "    $NAME.$DOMAIN\t with target\t $IP"

    read
}

function clear_instance() {
    local NAME=$1

    # Delete the previous instance if it exists
    if [ -f ../../configs/$NAME/deployment.yaml ]; then
        kubectl delete -f ../../configs/$NAME/deployment.yaml 2> /dev/null
    fi

    # Delete anything with the same name
    wiistock delete ingress $NAME                    2> /dev/null
    wiistock delete service $NAME                    2> /dev/null
    wiistock delete secret $NAME-tls                 2> /dev/null
    wiistock delete deployment $NAME                 2> /dev/null
}

function create_deployment() {
    local NAME=$1
    local REPLICAS_COUNT=$2
    local DOMAIN=$3
    local REPOSITORY=$4
    local BRANCH=$5
    
    local CONFIG=../../configs/$NAME/deployment.yaml
    local FULL_DOMAIN=$NAME.$DOMAIN
    local SECRET=$(openssl rand -base64 8 | tr --delete =/)
    
    cp kubernetes/deployment.yaml $CONFIG
    sed -i "s|VAR:INSTANCE_NAME|$NAME|g"              $CONFIG
    sed -i "s|VAR:REPLICAS_COUNT|$REPLICAS_COUNT|g"   $CONFIG
    sed -i "s|VAR:DOMAIN|$FULL_DOMAIN|g"              $CONFIG
    sed -i "s|VAR:REPOSITORY|$REPOSITORY|g"           $CONFIG
    sed -i "s|VAR:BRANCH|$BRANCH|g"                   $CONFIG
    sed -i "s|VAR:PARTITION_NAME|$NAME|g"             $CONFIG
    sed -i "s|VAR:DATABASE_HOST|${DATABASE[host]}|g"  $CONFIG
    sed -i "s|VAR:DATABASE_PORT|${DATABASE[port]}|g"  $CONFIG
    sed -i "s|VAR:DATABASE_USER|${DATABASE[user]}|g"  $CONFIG
    sed -i "s|VAR:DATABASE_PASS|${DATABASE[pass]}|g"  $CONFIG
    sed -i "s|VAR:DATABASE_NAME|$NAME|g"              $CONFIG
    sed -i "s|VAR:ENV|prod|g"                         $CONFIG
    sed -i "s|VAR:SECRET|$SECRET|g"                   $CONFIG

    for NUMBER in {1..5}; do
        if [ -n "${NAMES[$NUMBER]}" ]; then
            sed -i "s|VAR:NAME_$NUMBER|- name: ${NAMES[$NUMBER]}|g"        $CONFIG
            sed -i "s|VAR:VALUE_$NUMBER|  value: \"${VALUES[$NUMBER]}\"|g" $CONFIG
        else
            sed -i "s|VAR:NAME_$NUMBER||g"   $CONFIG
            sed -i "s|VAR:VALUE_$NUMBER||g" $CONFIG
        fi
    done

    wiistock apply -f $CONFIG
}

create_directories $NAME

request_configuration
request_database_creation $NAME
request_domains_creation $NAME $DOMAIN

clear_instance $NAME
create_deployment $NAME $REPLICAS_COUNT $DOMAIN $REPOSITORY $BRANCH
