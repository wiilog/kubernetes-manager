#!/bin/bash

PROGRAM_NAME=$(basename $0)
SCRIPT_DIRECTORY=$(dirname $BASH_SOURCE)
COMMAND=$1

declare -A TIMES
TIMES[imports]="*/30 * * * *"
TIMES[dashboard-feeds]="*/5 * * * *"
TIMES[average-requests]="0 20 * * *"

declare -A COMMANDS
COMMANDS[imports]="php /project/bin/console app:launch:imports"
COMMANDS[dashboard-feeds]="php /project/bin/console app:feed:dashboards"
COMMANDS[average-requests]="php /project/bin/console app:feed:average:requests"

function wiistock() {
    /usr/local/bin/kubectl --namespace=wiistock "$@"
}

function run() {
    local TEMPLATE=$1
    local COMMAND=$2

    local POD
    for POD in $(wiistock get pods --no-headers -l template=$TEMPLATE | tr -s ' ' | cut -d ' ' -f 1); do
        echo "Running $COMMAND on pod $POD"
        wiistock exec $POD -- ${COMMANDS[$COMMAND]} &
    done

    wait
}

function usage() {
    echo "Run CRON tasks on kubernetes"
    echo ""
    echo "USAGE:"
    echo "    $PROGRAM_NAME <command> [options]"
    echo ""
    echo "COMMANDS:"
    echo "    run <template> <task>                Run the specified task on the template"
    echo ""
    exit 0
}

if [ -n "$COMMAND" ]; then
    shift
fi

cd $SCRIPT_DIRECTORY

case $COMMAND in
    run)                run "$@" ;;
    *)                  usage "$@" ;;
esac