#!/bin/bash

NAME=$1; shift
DIRECTORY=../../configs/iot;

function rabbitmq() {
    kubectl --namespace=rabbitmq "$@"
}

function request_configuration() {
    echo ""
    echo "  Dipatch center configuration"
    read -p "Replicas count:   " REPLICAS_COUNT
    read -p "RabbitMQ IP:   " RABBITMQ_IP
    read -p "RabbitMQ user:   " RABBITMQ_USER
    read -p -s "RabbitMQ password:   " RABBITMQ_PWD
    read -p "RabbitMQ topic exchange key:   " RABBITMQ_TOPIC_SELECTOR_KEY
    read -p "Queue to listen on:   " QUEUE
    echo ""
}


function create_deployment() {
    local FULL_NAME="dispatch-center-$NAME"
    local CONFIG="$DIRECTORY/$FULL_NAME.yaml"

    cp kubernetes/dispatch-center.yaml "$CONFIG"

    sed -i "s|VAR:REPLICAS_COUNT|$REPLICAS_COUNT|g"                           "$CONFIG"
    sed -i "s|VAR:NAME|$NAME|g"                                               "$CONFIG"
    sed -i "s|VAR:RABBITMQ_IP|$RABBITMQ_IP|g"                                 "$CONFIG"
    sed -i "s|VAR:RABBITMQ_USER|$RABBITMQ_USER|g"                             "$CONFIG"
    sed -i "s|VAR:RABBITMQ_PWD|$RABBITMQ_PWD|g"                               "$CONFIG"
    sed -i "s|VAR:RABBITMQ_TOPIC_SELECTOR_KEY|$RABBITMQ_TOPIC_SELECTOR_KEY|g" "$CONFIG"
    sed -i "s|VAR:QUEUE|$QUEUE|g"                                             "$CONFIG"

    rabbitmq apply -f "$CONFIG"
}

mkdir -p "$DIRECTORY"
request_configuration
create_deployment

wait
