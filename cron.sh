#!/bin/bash

PROGRAM_NAME=$(basename $0)
SCRIPT_DIRECTORY=$(dirname $BASH_SOURCE)
COMMAND=$1

declare -A TIMES
TIMES[imports]="*/30 * * * *"
TIMES[scheduled-imports]="* * * * *"
TIMES[dashboard-feeds]="*/5 * * * *"
TIMES[dashboard-feeds-every-minute]="1-4,6-9,11-14,16-19,21-24,26-29,31-34,36-39,41-44,46-49,51-54,56-59 * * * *"
TIMES[average-requests]="0 20 * * *"
TIMES[alerts]="0 20 * * *"
TIMES[dispute-mails]="0 8 * * *"
TIMES[missions]="0 23 * * 0"

declare -A COMMANDS
COMMANDS[imports]="php /project/bin/console app:launch:imports"
COMMANDS[scheduled-imports]="php /project/bin/console app:launch:scheduled-imports"
COMMANDS[dashboard-feeds]="php /project/bin/console app:feed:dashboards"
COMMANDS[dashboard-feeds-every-minute]="php /project/bin/console app:feed:dashboards"
COMMANDS[average-requests]="php /project/bin/console app:feed:average:requests"
COMMANDS[alerts]="php /project/bin/console app:generate:alerts"
COMMANDS[dispute-mails]="php /project/bin/console app:mails-litiges"
COMMANDS[missions]="php /project/bin/console app:generate:mission"

declare -A SPECIFICS
SPECIFICS[dashboard-feeds-every-minute]="col1-prod col1-rec"
SPECIFICS[dispute-mails]="scs1-prod scs1-rec"
SPECIFICS[missions]="cl2-prod cl2-rec"

function wiistock() {
    /usr/local/bin/kubectl --namespace=wiistock "$@"
}

function run() {
    local TEMPLATE=$1
    local COMMAND=$2
    local INSTANCE=$3

    if [ -n "$INSTANCE" ]; then
        local POD=$(wiistock get pods --no-headers -l app=$INSTANCE | grep Running | tr -s ' ' | cut -d ' ' -f 1)
        if [ -n $POD ]; then
            echo "Running $COMMAND on pod $POD"
            wiistock exec $POD -- ${COMMANDS[$COMMAND]} &
        else
            echo "No pod found for app $INSTANCE"
        fi
    else
        local POD
        for POD in $(wiistock get pods --no-headers -l template=$TEMPLATE | grep Running | tr -s ' ' | cut -d ' ' -f 1); do
            if [ -n "${SPECIFICS[$COMMAND]}" ]; then
                local INSTANCES=${SPECIFICS[$COMMAND]}
                local SPECIFIC

                for SPECIFIC in $INSTANCES; do
                    if [[ $POD == $SPECIFIC* ]]; then
                        echo "Running specific $COMMAND on pod $POD"
                        wiistock exec $POD -- ${COMMANDS[$COMMAND]} &
                        break
                    fi
                done
            else
                echo "Running $COMMAND on pod $POD"
                wiistock exec $POD -- ${COMMANDS[$COMMAND]} &
            fi
        done
    fi

    wait
}

function usage() {
    echo "Run CRON tasks on kubernetes"
    echo ""
    echo "USAGE:"
    echo "    $PROGRAM_NAME <command> [options]"
    echo ""
    echo "COMMANDS:"
    echo "    run <template> <task> [instance]     Run the specified task on the template"
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