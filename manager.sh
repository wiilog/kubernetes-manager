#!/bin/bash

PROGRAM_NAME=$(basename $0)
SCRIPT_DIRECTORY=$(dirname $([ -L $0 ] && readlink -f $0 || echo $0))
COMMAND=$1

function wiistock() {
    kubectl --namespace=wiistock "$@"
}

function log() {
    echo "$(date '+%k:%M:%S') - $1"
}

function activate_maintenance() {
    local INSTANCE=$1
    local PODS=$(wiistock get pods -l app=$INSTANCE | grep "Running" | tr -s ' ' | cut -d ' ' -f 1)
    local PODS_COUNT=$(echo $PODS | wc -w)

    log "Rolling $PODS_COUNT pods to maintainance mode for $NAME, this step can take up to 5 minutes"
    
    local POD
    for POD in $PODS; do
        wiistock exec $POD -- /bootstrap/maintenance.sh
    done
}
  
function create_instance() {
    if [ $# -lt 2 ]; then
        echo "Illegal number of arguments, expected at least 2, found $#"
        exit 101
    fi

    local TEMPLATE=$1
    local NAME=$2
    shift 2

    # Check if template exists
    if [ ! -d templates/$TEMPLATE ]; then
        echo "Unknown template $TEMPLATE"
        exit 102
    fi

    (cd templates/$TEMPLATE; bash setup.sh $NAME $@)
}

function reconfigure() {
    if [ $# -lt 2 ]; then
        echo "Illegal number of arguments, expected at least 2, found $#"
        exit 101
    fi

    local TEMPLATE=$1
    local NAME=$2
    shift 2

    # Check if template exists
    if [ ! -d templates/$TEMPLATE ]; then
        echo "Unknown template $TEMPLATE"
        exit 102
    fi

    # This warning applies to modifying the volumes in deployment.yaml
    echo "Reconfiguring an instance DOES NOT support modifying persistent volumes"
    echo "or persistent volume claims. Doing so will result in data loss."

    read -p "Continue?" REPLY
    if [[ ! $REPLY =~ ^[Yy1]$ ]]; then
        exit 0
    fi
    
    (cd templates/$TEMPLATE; bash setup.sh $NAME $@ --reconfigure)
}

function deploy() {
    local INSTANCE
    local INSTANCES

    if [[ $@ == "prod" ]]; then
        INSTANCES=$(wiistock get deployments | cut -d' ' -f1 | grep $@ && echo demo)
    elif [[ $@ == "rec" ]]; then
        INSTANCES=$(wiistock get deployments | cut -d' ' -f1 | grep $@ && echo test)
    else
        INSTANCES=$@
    fi

    log "Deploying $(echo $INSTANCES | wc -w) instances"

    for INSTANCE in $INSTANCES; do
        do_deploy $INSTANCE &
    done
    wait

    if [ $# -gt 1 ]; then
        log "Successfully deployed $(echo $INSTANCES | wc -w) instances"
    fi
}

function do_deploy() {
    if [ $# -ne 1 ]; then
        echo "Illegal number of arguments, expected between 1, found $#"
        exit 201
    fi

    local NAME=$1

    # Check if deployment exists
    local PODS=$(wiistock get deployments | grep "$NAME*")
    if [ -z "$PODS" ]; then
        echo "Unknown instance \"$NAME\""
        exit 202
    fi
    
    if [[ -n $(wiistock get pods -l app=$NAME | egrep "Init:[0-9]+/1") ]]; then
        log "$NAME - An instance is already being deployed"
        exit 0
    fi

    echo "$(date '+%k:%M:%S') - $NAME - Starting database backup"
    DATABASE_NAME=${NAME//-}
    DATABASE_USER=${NAME%-*}
    DATABASE_PASSWORD=$(cat configs/passwords/$DATABASE_USER)

    # Save the database in a detached thread
    mysqldump $DATABASE_NAME --no-tablespaces \
        --host="cb249510-001.dbaas.ovh.net" \
        --user="$DATABASE_USER" \
        --port=35403 \
        --password="$DATABASE_PASSWORD" > /root/backups/$NAME-$(date '+%Y-%m-%d-%k-%M-%s').sql 2> /dev/null &

    log "$NAME - Updating deployment"
    wiistock rollout restart deployment $NAME > /dev/null

    # Temporary to remove the redeploy label
    for POD in $(wiistock get pods --no-headers -l app=$NAME | tr -s ' ' | cut -d ' ' -f 1); do
        wiistock label pod $POD redeploy- > /dev/null
    done

    # Wait for the pod to start initializing and get its name
    while [[ -z $(wiistock get pods -l app=$NAME | grep "Init:1/2") ]]; do
        sleep 1
    done; 
    
    local POD=$(wiistock get pods -l app=$NAME | grep "Init:1/2" | tr -s ' ' | cut -d ' ' -f 1)
    
    log "$NAME - Waiting for pods to reach migrations step"
    
    # Wait for the file to be created and get its content
    while [[ -z $(wiistock exec $POD -c initializer -- cat /tmp/migrations 2> /dev/null) ]]; do
        sleep 1
    done;

    # Reattach the detached database backup thread
    wait
    log "$NAME - Finished database backup"

    local MIGRATIONS=$(wiistock exec $POD -c initializer -- cat /tmp/migrations 2> /dev/null)

    if [ "$MIGRATIONS" -eq 1 ]; then
        activate_maintenance $NAME
        wiistock exec $POD -c initializer -- sh -c "echo '1' > /tmp/ready"
    else
        log "$NAME - No migration detected, proceeding with deployment without maintenance, this step can take up to 5 minutes"
    fi

    while [[ -z $(wiistock get pods -l app=$NAME | grep $POD | grep "Running") ]]; do
        sleep 1
    done;

    log "$NAME - Successfully deployed"
}

function open() {
    local INSTANCE=$1
    local POD=$(wiistock get pods --no-headers | awk -F ' ' '{print $1}' | grep $INSTANCE)
    
    if [ -z "$POD" ]; then
        echo "No instance found matching the provided name"
    elif [ $(echo $POD | wc -w) != 1 ]; then
        echo "There are more than 1 instances matching this name"
    else
        wiistock exec -it $POD -- sh -c "apk add nano bash > /dev/null && bash && apk del nano bash > /dev/null"
    fi
}

function cache() {
    if [[ $# -lt 1 || $# -gt 2 ]]; then
        echo "Illegal number of arguments, expected between 1 and 2, found $#"
        exit 201
    fi

    local TEMPLATE=$1

    if [ ! -d templates/$TEMPLATE ]; then
        echo "Unknown template $TEMPLATE"
        exit 302
    fi

    if [ ! -f templates/$TEMPLATE/kubernetes/cache.yaml ]; then
        echo "Template $TEMPLATE does not have a cache"
        exit 303
    fi

    if [ -z "$(wiistock get pods | grep $TEMPLATE-cache)" ]; then
        wiistock apply -f templates/$TEMPLATE/kubernetes/cache.yaml
    else
        wiistock delete pod $TEMPLATE-cache
        wiistock apply -f templates/$TEMPLATE/kubernetes/cache.yaml
    fi
}

function delete() {
    if [[ $# -ne 1 ]]; then
        echo "Illegal number of arguments, expected 1, found $#"
        exit 201
    fi

    local NAME=$1
 
    if [ ! -d configs/$NAME ]; then
        echo "Unknown instance \"$NAME\""
        exit 202
    fi

    wiistock delete -f configs/$NAME/deployment.yaml 2> /dev/null
    rm -rf configs/$NAME
}

function publish() {
    local IMAGE=$1

    if [ -n "$IMAGE" ]; then
        echo "Building and pushing wiilog/$IMAGE"
        docker build -t wiilog/$IMAGE:latest images/$IMAGE > /dev/null
        docker push wiilog/$IMAGE:latest                   > /dev/null
    else
        # Build and push all images in the `images` folder
        local IMAGE
        while IFS=$' \t\n\r' read -r IMAGE; do
            echo "Building and pushing wiilog/$IMAGE"
            docker build -t wiilog/$IMAGE:latest images/$IMAGE > /dev/null
            docker push wiilog/$IMAGE:latest                   > /dev/null
        done < images/order
    fi
}

function self_update() {
    if [ "$UPDATE_GUARD" ]; then
        return
    fi
    
    export UPDATE_GUARD=YES

    # Remove any modifications
    git checkout HEAD -- images templates cron.sh install.sh manager.sh README.md
    git fetch > /dev/null 2> /dev/null

    if [ $(git rev-parse HEAD) == $(git rev-parse @{u}) ]; then
        echo "Already the latest version"
    else
        echo "New version found, pulling update"
        git pull > /dev/null 2> /dev/null
    fi

    chmod a+x manager.sh
    chmod a+x cron.sh
    exit 0
}

function usage() {
    echo "Manage and deploy kubernetes instances"
    echo ""
    echo "USAGE:"
    echo "    $PROGRAM_NAME <command> [options]"
    echo ""
    echo "COMMANDS:"
    echo "    create-instance <template> <name>    Create an instance"
    echo "    reconfigure <template> <name>        Recreates the configuration files and"
    echo "                                         apply them to the running instance"
    echo "    deploy <...instances>                Deploys the given instance(s)"
    echo "    open <instance>                      Opens a bash in the instance"
    echo "    cache <template>                     Creates or updates a template's cache"
    echo "    delete <instance>                    Deletes a deployment"
    echo "    publish <image>                      Builds and pushes the docker image"
    echo "    self-update                          Updates the script from git repository"
    echo ""
    exit 0
}

if [ -n "$COMMAND" ]; then
    shift
fi

if [[ -z $(kubectl get namespaces | grep "wiistock") ]]; then
    kubectl create namespace wiistock > /dev/null
fi

cd $SCRIPT_DIRECTORY
mkdir -p configs/passwords

case $COMMAND in
    create-instance)    create_instance "$@" ;;
    reconfigure)        reconfigure "$@" ;;
    deploy)             deploy "$@" ;;
    open)               open "$@" ;;
    cache)              cache "$@" ;;
    delete)             delete "$@" ;;
    publish)            publish "$@" ;;
    self-update)        self_update "$@" ;;
    *)                  usage "$@" ;;
esac