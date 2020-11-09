#!/bin/bash

NAME=$1

function wiistock() {
    kubectl --namespace=wiistock "$@"
}

function clear_instance() {
    local NAME=$1
    local ENVIRONMENT=$2

    wiistock delete deployment $NAME                  2> /dev/null
    wiistock delete pvc $NAME-letsencrypt             2> /dev/null
    wiistock delete pvc $NAME-uploads                 2> /dev/null
    wiistock delete pv wiistock-$NAME-letsencrypt-pv  2> /dev/null
    wiistock delete pv wiistock-$NAME-uploads-pv      2> /dev/null
}

function delete_configs() {
    local NAME=$1

    rm -rf ../configs/$NAME
}

clear_instance $NAME &
clear_instance $NAME &
delete_configs $NAME &
wait