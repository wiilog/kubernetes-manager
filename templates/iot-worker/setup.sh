#!/bin/bash

NAME=$1; shift
DIRECTORY=../../configs/iot;

function iot() {
    kubectl --namespace=iot "$@"
}

function request_configuration() {
    echo ""
    echo "  Worker configuration"
    read -p "Replicas count:   " REPLICAS_COUNT
    read -p "RabbitMQ IP:   " RABBITMQ_IP
    read -p "RabbitMQ user:   " RABBITMQ_USER
    read -s -p "RabbitMQ password:   " RABBITMQ_PWD
    read -p "Queue to listen on:   " QUEUE
    read -p "IOT endpoint:   " IOT_ENDPOINT
    read -p "IOT auth token:   " IOT_AUTH_TOKEN
    echo ""
}


function create_deployment() {
    local FULL_NAME="worker-$NAME"
    local CONFIG="$DIRECTORY/$FULL_NAME.yaml"

    cp kubernetes/worker.yaml "$CONFIG"

    sed -i "s|VAR:REPLICAS_COUNT|$REPLICAS_COUNT|g" "$CONFIG"
    sed -i "s|VAR:NAME|$NAME|g"                     "$CONFIG"
    sed -i "s|VAR:RABBITMQ_IP|$RABBITMQ_IP|g"       "$CONFIG"
    sed -i "s|VAR:RABBITMQ_USER|$RABBITMQ_USER|g"   "$CONFIG"
    sed -i "s|VAR:RABBITMQ_PWD|$RABBITMQ_PWD|g"     "$CONFIG"
    sed -i "s|VAR:QUEUE|$QUEUE|g"                   "$CONFIG"
    sed -i "s|VAR:IOT_ENDPOINT|$IOT_ENDPOINT|g"     "$CONFIG"
    sed -i "s|VAR:IOT_AUTH_TOKEN|$IOT_AUTH_TOKEN|g" "$CONFIG"

    iot apply -f "$CONFIG"
}

mkdir -p "$DIRECTORY"
request_configuration
create_deployment

wait
