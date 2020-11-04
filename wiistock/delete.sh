#!/bin/bash

NAME=$1

function wiistock() {
    kubectl --namespace=wiistock "$@"
}

function clear_instance() {
    local NAME=$1
    local ENVIRONMENT=$2

    wiistock delete deployment $NAME-$ENVIRONMENT                  2> /dev/null
    wiistock delete pvc $NAME-$ENVIRONMENT-letsencrypt             2> /dev/null
    wiistock delete pvc $NAME-$ENVIRONMENT-uploads                 2> /dev/null
    wiistock delete pv wiistock-$NAME-$ENVIRONMENT-letsencrypt-pv  2> /dev/null
    wiistock delete pv wiistock-$NAME-$ENVIRONMENT-uploads-pv      2> /dev/null
}

function delete_configs() {
    local NAME=$1

    rm -rf ../configs/$NAME
}

clear_instance $NAME "rec"  &
clear_instance $NAME "prod" &
delete_configs $NAME        &
wait