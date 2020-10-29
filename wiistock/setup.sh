# Define known environment variables
INSTANCE_NAME=$1
DASHBOARD_TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
SECRET=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
LOGGER_URL="https://logs.follow-gt.fr"
DATABASE_HOST=cb249510-001.dbaas.ovh.net
DATABASE_PORT=35403

echo ""
echo "  Kubernetes configuration"
read -p "Replicas count:      " REPLICAS_COUNT
read -p "Branches suffix:     " BRANCHES_SUFFIX
read -p "Base domain name:    " DOMAIN
echo ""

echo "Create the following user and databases on OVH panel accessible"
echo "by the user and press enter when OVH is done creating everything"
echo "    User      \"${INSTANCE_NAME}\""
echo "    Database  \"${INSTANCE_NAME}rec\""
echo "    Database  \"${INSTANCE_NAME}prod\""
read

echo "Create the user \"${INSTANCE_NAME}\" with admin rights on both databases."
echo "The password must not contain ?, &, @, / or |"
read -p "Password:           " DATABASE_PASS
while [[ $DATABASE_PASS =~ [\?\&@\/\|] ]]; do
    echo "The password must not contain ?, &, @, / or |"
    read -p "Password:           " DATABASE_PASS
done

echo ""
echo ""
echo "  Wiistock configuration"
read -p "Locale:              " LOCALE
read -p "Client:              " CLIENT
read -p "Forbidden phones:    " FORBIDDEN_PHONES

# Replace all characters by spaces for spacing
INSTANCE_SPACES=$(echo $INSTANCE_NAME | sed -e 's|[ a-z]| |g')

echo ""
echo "Create the following partitions on OVH panel, allow access from the"
echo "following 3 IPs and press enter when OVH is done creating them"
echo "    ${INSTANCE_NAME}rec     |    51.210.121.167"
echo "    ${INSTANCE_NAME}prod    |    51.210.125.224"
echo "    ${INSTANCE_SPACES}        |    51.210.127.44"
read

echo "  Deleting previous deployments of \"$INSTANCE_NAME-rec\" and \"$INSTANCE_NAME-prod\""
kubectl delete deployment $INSTANCE_NAME-rec-deployment  2> /dev/null
kubectl delete pvc $INSTANCE_NAME-rec-letsencrypt        2> /dev/null
kubectl delete pvc $INSTANCE_NAME-rec-uploads            2> /dev/null
kubectl delete pv $INSTANCE_NAME-rec-letsencrypt-pv      2> /dev/null
kubectl delete pv $INSTANCE_NAME-rec-uploads-pv          2> /dev/null
kubectl delete deployment $INSTANCE_NAME-prod-deployment 2> /dev/null
kubectl delete pvc $INSTANCE_NAME-prod-letsencrypt       2> /dev/null
kubectl delete pvc $INSTANCE_NAME-prod-uploads           2> /dev/null
kubectl delete pv $INSTANCE_NAME-prod-letsencrypt-pv     2> /dev/null
kubectl delete pv $INSTANCE_NAME-prod-uploads-pv         2> /dev/null

mkdir -p ../instances
mkdir -p ../instances/$INSTANCE_NAME

REC_BALANCER_CONFIG=../instances/$INSTANCE_NAME/rec-balancer.yaml
PROD_BALANCER_CONFIG=../instances/$INSTANCE_NAME/prod-balancer.yaml

if [[ -z $(kubectl get services | egrep "$INSTANCE_NAME-rec|$INSTANCE_NAME-prod") ]]; then
    echo ""
    echo "  Creating load balancers for \"$INSTANCE_NAME-rec\" and \"$INSTANCE_NAME-prod\""
    cp balancer.yaml $REC_BALANCER_CONFIG
    sed -i "s|VAR:INSTANCE_NAME|$INSTANCE_NAME-rec|g"     $REC_BALANCER_CONFIG
    kubectl apply -f $REC_BALANCER_CONFIG

    cp balancer.yaml $PROD_BALANCER_CONFIG
    sed -i "s|VAR:INSTANCE_NAME|$INSTANCE_NAME-prod|g"    $PROD_BALANCER_CONFIG
    kubectl apply -f $PROD_BALANCER_CONFIG

    echo ""
    echo "  Waiting for load balancers to get their IP assigned"
    while [[ ! $(kubectl get services | grep $INSTANCE_NAME-rec | tr -s ' ' | cut -d ' ' -f 4) =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do
        sleep 2
    done

    while [[ ! $(kubectl get services | grep $INSTANCE_NAME-prod | tr -s ' ' | cut -d ' ' -f 4) =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do
        sleep 2
    done
    
    echo ""
else
    echo ""
    echo "  Keeping existing load balancers"
    echo ""
fi

REC_CONFIG=../instances/$INSTANCE_NAME/rec-deployment.yaml
REC_DOMAIN=${INSTANCE_NAME}-rec.${DOMAIN}
REC_IP=$(kubectl get services | grep $INSTANCE_NAME-rec | tr -s ' ' | cut -d ' ' -f 4)

PROD_CONFIG=../instances/$INSTANCE_NAME/prod-deployment.yaml
PROD_DOMAIN=${INSTANCE_NAME}-prod.${DOMAIN}
PROD_IP=$(kubectl get services | grep $INSTANCE_NAME-prod | tr -s ' ' | cut -d ' ' -f 4)

echo "Create the following two domains and press enter when done"
echo -e "    $REC_DOMAIN\t with target\t $REC_IP"
echo -e "    $PROD_DOMAIN\t with target\t $PROD_IP"
read

echo "  Creating and deploying \"$INSTANCE_NAME-rec\""
cp deployment.yaml $REC_CONFIG
sed -i "s|VAR:INSTANCE_NAME|$INSTANCE_NAME-rec|g"     $REC_CONFIG
sed -i "s|VAR:REPLICAS_COUNT|1|g"                     $REC_CONFIG
sed -i "s|VAR:BRANCH|recette-$BRANCHES_SUFFIX|g"      $REC_CONFIG
sed -i "s|VAR:PARTITION_NAME|${INSTANCE_NAME}rec|g"   $REC_CONFIG
sed -i "s|VAR:DOMAIN|${REC_DOMAIN}|g"                 $REC_CONFIG
sed -i "s|VAR:DATABASE_HOST|${DATABASE_HOST}|g"       $REC_CONFIG
sed -i "s|VAR:DATABASE_PORT|${DATABASE_PORT}|g"       $REC_CONFIG
sed -i "s|VAR:DATABASE_USER|${INSTANCE_NAME}|g"       $REC_CONFIG
sed -i "s|VAR:DATABASE_PASS|${DATABASE_PASS}|g"       $REC_CONFIG
sed -i "s|VAR:DATABASE_NAME|${INSTANCE_NAME}rec|g"    $REC_CONFIG
sed -i "s|VAR:DOMAIN|${REC_DOMAIN}|g"                 $REC_CONFIG
sed -i "s|VAR:ENV|prod|g"                             $REC_CONFIG
sed -i "s|VAR:SECRET|${SECRET}|g"                     $REC_CONFIG
sed -i "s|VAR:LOCALE|${LOCALE}|g"                     $REC_CONFIG
sed -i "s|VAR:CLIENT|${CLIENT}|g"                     $REC_CONFIG
sed -i "s|VAR:URL|https://${REC_DOMAIN}|g"            $REC_CONFIG
sed -i "s|VAR:LOGGER|${LOGGER_URL}|g"                 $REC_CONFIG
sed -i "s|VAR:FORBIDDEN_PHONES|${FORBIDDEN_PHONES}|g" $REC_CONFIG
sed -i "s|VAR:DASHBOARD_TOKEN|${DASHBOARD_TOKEN}|g"   $REC_CONFIG
kubectl apply -f $REC_CONFIG

echo ""
echo "  Creating and deploying \"$INSTANCE_NAME-prod\""
cp deployment.yaml $PROD_CONFIG
sed -i "s|VAR:INSTANCE_NAME|$INSTANCE_NAME-prod|g"    $PROD_CONFIG
sed -i "s|VAR:REPLICAS_COUNT|$REPLICAS_COUNT|g"       $PROD_CONFIG
sed -i "s|VAR:BRANCH|master-$BRANCHES_SUFFIX|g"       $PROD_CONFIG
sed -i "s|VAR:PARTITION_NAME|${INSTANCE_NAME}prod|g"  $PROD_CONFIG
sed -i "s|VAR:DOMAIN|${PROD_DOMAIN}|g"                $PROD_CONFIG
sed -i "s|VAR:DATABASE_HOST|${DATABASE_HOST}|g"       $PROD_CONFIG
sed -i "s|VAR:DATABASE_PORT|${DATABASE_PORT}|g"       $PROD_CONFIG
sed -i "s|VAR:DATABASE_USER|${INSTANCE_NAME}|g"       $PROD_CONFIG
sed -i "s|VAR:DATABASE_PASS|${DATABASE_PASS}|g"       $PROD_CONFIG
sed -i "s|VAR:DATABASE_NAME|${INSTANCE_NAME}prod|g"   $PROD_CONFIG
sed -i "s|VAR:ENV|prod|g"                             $PROD_CONFIG
sed -i "s|VAR:SECRET|${SECRET}|g"                     $PROD_CONFIG
sed -i "s|VAR:LOCALE|${LOCALE}|g"                     $PROD_CONFIG
sed -i "s|VAR:CLIENT|${CLIENT}|g"                     $PROD_CONFIG
sed -i "s|VAR:URL|https://${PROD_DOMAIN}|g"           $PROD_CONFIG
sed -i "s|VAR:LOGGER|${LOGGER_URL}|g"                 $PROD_CONFIG
sed -i "s|VAR:FORBIDDEN_PHONES|${FORBIDDEN_PHONES}|g" $PROD_CONFIG
sed -i "s|VAR:DASHBOARD_TOKEN|${DASHBOARD_TOKEN}|g"   $PROD_CONFIG
kubectl apply -f $PROD_CONFIG