#!/bin/bash

PROGRAM_NAME=$(basename $0)
SCRIPT_DIRECTORY=$(dirname $([ -L $0 ] && readlink -f $0 || echo $0))
COMMAND=$1

OPTIONS="$@"

function has_option() {
    MATCH="$1"

    if test "${OPTIONS#*$MATCH}" != "$OPTIONS"; then
        return 0
    else
        return 1
    fi
}

function wiistock() {
    kubectl --namespace=wiistock "$@"
}

function activate_maintenance() {
    local INSTANCE=$1
    local PODS=$(wiistock get pods -l app=$INSTANCE | grep "Running" | tr -s ' ' | cut -d ' ' -f 1)
    local PODS_COUNT=$(echo $PODS | wc -w)

    echo "Rolling $PODS_COUNT pods to maintainance mode for $NAME"
    
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
    if [ ! -d "./$TEMPLATE" ]; then
        echo "Unknown template $TEMPLATE"
        exit 102
    fi

    (cd $TEMPLATE; bash setup.sh $NAME $@)
}

function path() {
    if [ $# -lt 2 ]; then
        echo "Illegal number of arguments, expected at least 2, found $#"
        exit 101
    fi

    echo "Patching an instance DOES NOT support modifying persistent volumes"
    echo "or persistent volume claims. Doing so will result in data loss."
}

function deploy() {
    echo "Deploying $# instances"

    local INSTANCE
    for INSTANCE in $@; do
        do_deploy $INSTANCE &
    done

    wait
}

function do_deploy() {
    if [[ $# -ne 1 ]]; then
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
        echo "An instance of \"$NAME\" is already being deployed"
        exit 203
    fi

    echo "Starting database $NAME backup"
    DATABASE_NAME=${NAME//-}
    DATABASE_USER=${NAME%-*}
    DATABASE_PASSWORD=$(cat configs/passwords/$DATABASE_USER)

    # Save the database in a detached thread
    mysqldump $DATABASE_NAME --no-tablespaces \
        --host="cb249510-001.dbaas.ovh.net" \
        --user="$DATABASE_USER" \
        --port=35403 \
        --password="$DATABASE_PASSWORD" > /root/backups/${NAME}_$(date '+%Y-%m-%d-%k-%M-%s').sql 2> /dev/null &

    echo "Updating deployment $NAME"
    wiistock patch deployment $NAME -p "{\"spec\": {\"template\": {\"metadata\": { \"labels\": { \"redeploy\": \"$(date +%s)\"}}}}}" > /dev/null
    
    # Wait for the pod to start initializing and get its name
    while [[ -z $(wiistock get pods -l app=$NAME | grep "Init:1/2") ]]; do
        sleep 1
    done; 
    
    local POD=$(wiistock get pods -l app=$NAME | grep "Init:1/2" | tr -s ' ' | cut -d ' ' -f 1)
    
    echo "Waiting for $NAME pods to reach migrations step"
    
    # Wait for the file to be created and get its content
    while [[ -z $(wiistock exec $POD -c initializer -- cat /tmp/migrations 2> /dev/null) ]]; do
        sleep 1
    done;

    # Reattach the detached database backup thread
    wait
    echo "Finished $NAME database backup"

    local MIGRATIONS=$(wiistock exec $POD -c initializer -- cat /tmp/migrations 2> /dev/null)

    if [ "$MIGRATIONS" -eq 1 ]; then
        activate_maintenance $NAME
        wiistock exec $POD -c initializer -- sh -c "echo '1' > /tmp/ready"
    else
        echo "No migration detected, proceeding $NAME deployment without maintenance"
    fi
}

function open() {
    local INSTANCE=$1
    local POD=$(kubectl get pods -n wiistock --no-headers=true | awk -F ' ' '{print $1}' | grep $INSTANCE)
    
    if [ -z $POD ]; then
        echo "No instance found matching the provided name";
    else
        kubectl exec -n wiistock -it $POD -- sh -c "apk add nano bash > /dev/null && bash && apk del nano bash > /dev/null";
    fi
}

function cache() {
    if [[ $# -lt 1 || $# -gt 2 ]]; then
        echo "Illegal number of arguments, expected between 1 and 2, found $#"
        exit 201
    fi

    local TEMPLATE=$1

    if [ ! -d "./$TEMPLATE" ]; then
        echo "Unknown template $TEMPLATE"
        exit 302
    fi

    if [ ! -f "./$TEMPLATE/kubernetes/cache.yaml" ]; then
        echo "Template $TEMPLATE does not have a cache"
        exit 303
    fi

    if [ -z "$(wiistock get pods | grep $TEMPLATE-cache)" ]; then
        wiistock apply -f $TEMPLATE/kubernetes/cache.yaml
    else
        wiistock delete pod $TEMPLATE-cache
        wiistock apply -f $TEMPLATE/kubernetes/cache.yaml
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

    git fetch > /dev/null 2> /dev/null

    if [ $(git rev-parse HEAD) == $(git rev-parse @{u}) ]; then
        echo "Already the latest version."
        exit 0
    else
        echo "New version found, pulling update"
        git pull > /dev/null 2> /dev/null
        exit 0
    fi

    chmod a+x manager.sh
    chmod a+x cron.sh
}

function usage() {
    echo "Manage and deploy kubernetes instances"
    echo ""
    echo "USAGE:"
    echo "    $PROGRAM_NAME <command> [options]"
    echo ""
    echo "COMMANDS:"
    echo "    create-instance <template> <name>    Create an instance"
    echo "    patch <template> <name>              Recreates the configuration files and"
    echo "                                         apply them to the running instance"
    echo "    deploy <...instances>                Deploys the given instance(s)"
    echo "                                         or all environments if not specified"
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
    patch)              patch "$@" ;;
    deploy)             deploy "$@" ;;
    open)               open "$@" ;;
    cache)              cache "$@" ;;
    delete)             delete "$@" ;;
    publish)            publish "$@" ;;
    self-update)        self_update "$@" ;;
    *)                  usage "$@" ;;
esac