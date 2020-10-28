DASHBOARD_TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
SECRET=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

echo "KUBERNETES CONFIGURATION"
read -p "Instance name:  " INSTANCE_NAME
read -p "Replicas count: " REPLICAS_COUNT
echo ""
echo "SYMFONY ENVIRONMENT"
read -p "Database URL:   " INSTANCE_NAME