#!/bin/sh
instance="$1";
podName=$(kubectl get pods -n wiistock --no-headers=true | awk -F ' ' '{print $1}' | grep $instance);
kubectl exec -n wiistock -it $podName -- sh;
