#!/bin/bash
DEFAULT_REGION="eu-central-1"
DEFAULT_CLUSTER_DOMAIN="k8s.example.local"
DEFAULT_CLUSTER_NAME="develop"
DEFAULT_NET=1
DEFAULT_NODES=3
DEFAULT_MAX_NODES=5
DEFAULT_PUBLIC_DOMAIN="develop.example.com"
DEFAULT_AUTOSCALING_GROUP="terraform-tf-eks"
DEFAULT_K8S_VERSION="1.19"
DEFAULT_INSTANCE_TYPE="t3.large"

P_PARAMS=()
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in 
        -r|--region)
        REGION="$2"
        shift
        shift
        ;;
        -d|--domain)
        CLUSTER_DOMAIN="$2"
        shift
        shift
        ;;
        -n|--name)
        CLUSTER_NAME="$2"
        shift
        shift
        ;;
        -p|--public-domain)
        PUBLIC_DOMAIN="$2"
        shift
        shift
        ;;
        --net)
        NET="$2"
        shift
        shift
        ;;
        --nodes)
        NODES="$2"
        shift
        shift
        ;;
        --max-nodes)
        MAX_NODES="$2"
        shift
        shift
        ;;
        --autoscaling-group)
        AUTOSCALING_GROUP="$2"
        shift
        shift
        ;;
        --k8s-version)
        K8S_VERSION="$2"
        shift
        shift
        ;;
        --instance)
        INSTANCE_TYPE="$2"
        shift
        shift
        ;;
#        --whitelist)
#        WHITELIST="$2"
#        shift
#        shift
#        ;;
        *)
        P_PARAMS+=("$1")
        shift
        ;;
    esac
done

if [[ -z $REGION ]]; then
    REGION=$DEFAULT_REGION
fi

if [[ -z $CLUSTER_DOMAIN ]]; then
    CLUSTER_DOMAIN=$DEFAULT_CLUSTER_DOMAIN
fi

if [[ -z $CLUSTER_NAME ]]; then
    CLUSTER_NAME=$DEFAULT_CLUSTER_NAME
fi

if [[ -z $PUBLIC_DOMAIN ]]; then
    PUBLIC_DOMAIN=$DEFAULT_PUBLIC_DOMAIN
fi

if [[ -z $NET ]]; then
    NET=$DEFAULT_NET
fi

if [[ -z $NODES ]]; then
    NODES=$DEFAULT_NODES
fi

if [[ -z $MAX_NODES ]]; then
    MAX_NODES=$DEFAULT_MAX_NODES
fi

if [[ -z $AUTOSCALING_GROUP ]]; then
    AUTOSCALING_GROUP=$DEFAULT_AUTOSCALING_GROUP
fi

if [[ -z $K8S_VERSION ]]; then
    K8S_VERSION=$DEFAULT_K8S_VERSION
fi

if [[ -z $INSTANCE_TYPE ]]; then 
    INSTANCE_TYPE=$DEFAULT_INSTANCE_TYPE
fi

if [[ -z $WHITELIST ]]; then
    PUBLIC_IP="$(dig +short myip.opendns.com @resolver1.opendns.com -4)/32"
    WHITELIST=$(printf '"%s"' $PUBLIC_IP)
fi

PROJECT_NAME="$CLUSTER_NAME.$CLUSTER_DOMAIN"
TERRAFORM_BUCKET="terraform-$CLUSTER_NAME-$CLUSTER_DOMAIN"

set -- "${P_PARAMS[@]}"

print() {
    printf "\nProject-Name:        $PROJECT_NAME\n"
    printf   "Region:              $REGION\n"
    printf   "Cluster-Name:        $CLUSTER_NAME\n"
    printf   "Cluster-Domain:      $CLUSTER_DOMAIN\n"
    printf   "Public-Domain:       $PUBLIC_DOMAIN\n"
    printf   "Net-Index:           $NET\n"
    printf   "Instance-Type:       $INSTANCE_TYPE\n"
    printf   "Nodes:               $NODES\n"
    printf   "Max-Nodes:           $MAX_NODES\n"
    printf   "Autoscaling-Group:   $AUTOSCALING_GROUP\n"
    printf   "Bucket:              $TERRAFORM_BUCKET\n"
    printf   "Whitelisted-IPs:     $WHITELIST\n\n"
}

help() {
    printf "usage: cluster.sh <command> [optional arguments]\n\n"
    printf "commands:\n"
    printf "  info      Show parameters used by cluster-creation\n"
    printf "  plan      Plans the configured infrastructure\n"
    printf "\noptional arguments:\n"
    printf "  -r, --region           Sets AWS-Region for the cluster\n"
    printf "  -d, --domain           Define cluster-domain\n"
    printf "  -n, --name             Set cluster-name\n"
    printf "  -p, --public-domain    Public domain-name\n"
    printf "  --net                  Set the net index\n"
    printf "  --nodes                Amount of nodes to start\n"
    printf "  --max-nodes            Maximum amount of nodes to scale to\n"
    printf "  --autoscaling-group    Set the autoscaling-group name\n"
#    printf "  --whitelist            Set whitelisted CIDR-List "<cidr-1>", "<cidr-2>", and so on\n"
}

createSshKeys() {
    printf "Create cluster-key:\n"
    mkdir ./keys
    if test -f "./keys/cluster_key"; then
        printf "Cluster-key exists\n"
    else
        ssh-keygen -t rsa -b 4096 -C "k8s@$PROJECT_NAME" -f ./keys/cluster_key -q -N ""
        printf "Cluster-key created\n"
    fi
}

createBucket() {
    printf "Check bucket $TERRAFORM_BUCKET\n"
    if aws s3api head-bucket --bucket "$TERRAFORM_BUCKET" 2>/dev/null; then
        printf "Bucket exists\n"
    else
        printf "create bucket '$TERRAFORM_BUCKET'\n"
        if aws s3api create-bucket --bucket "$TERRAFORM_BUCKET" --region "$REGION" --create-bucket-configuration LocationConstraint=$REGION 2>/dev/null; then
            printf "Bucket created\n"
            if aws s3api put-bucket-versioning --region "$REGION" --bucket "$TERRAFORM_BUCKET" --versioning-configuration Status=Enabled 2>/dev/null; then
                printf "Bucket is versioned\n"
            else
                printf "Could not set bucket as versioned\n"
            fi

            if aws s3api put-bucket-encryption --region "$REGION" --bucket "$TERRAFORM_BUCKET" --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}' 2>/dev/null; then
                printf "Enable bucket encryption\n"
            else
                printf "Could not enable bucket encryption\n"
            fi
        else
            printf "Could not create brucket\n\nAborting\n\n"
            exit 1
        fi
    fi
}

initTerraform() {
    createSshKeys
    createBucket
    printf "Initialize terraform\n"
    #terraform init -backend-config "bucket=$TERRAFORM_BUCKET" -backend-config "key=file.state" -backend-config "region=$REGION"
    if terraform init -backend-config "bucket=$TERRAFORM_BUCKET" -backend-config "key=file.state" -backend-config "region=$REGION" 2>/dev/null; then
        printf "Initialized\n"
    else 
        printf "Could not initialize terraform\n\nAborting\n\n"
        exit 1
    fi
    if terraform workspace list | grep -q "$CLUSTER_NAME"; then
        printf "Select workspace '$CLUSTER_NAME'\n"
        terraform workspace select "$CLUSTER_NAME"
    else
        printf "Create workspace '$CLUSTER_NAME'\n"
        terraform workspace new "$CLUSTER_NAME"
        terraform workspace select "$CLUSTER_NAME"
    fi
}

planInfra() {
    initTerraform
    printf "Planning infrastructure\n"
    
    cat >cluster.tfvars <<EOL
cluster_name = "$CLUSTER_NAME"
cluster_domain = "$CLUSTER_DOMAIN"
vpc_network_index = "$NET"
region = "$REGION"
public_domain = "$PUBLIC_DOMAIN"
node_count = "$NODES"
max_node_count = "$MAX_NODES"
autoscaling_group_name = "$AUTOSCALING_GROUP"
k8s_version = "$K8S_VERSION"
node_instance_type = "$INSTANCE_TYPE"
whitelisted_hosts = [
    $WHITELIST
]
EOL

    #if terraform plan -out "$PROJECT_NAME.plan" -var "cluster_name=$CLUSTER_NAME" -var "cluster_domain=$CLUSTER_DOMAIN" -var "vpc_network_index=$NET" -var "region=$REGION" -var "public_domain=$PUBLIC_DOMAIN" -var "node_count=$NODES" -var "max_node_count=$MAX_NODES" -var "autoscaling_group_name=$AUTOSCALING_GROUP" -var "k8s_version=$K8S_VERSION" -var whitelisted_hosts=$WHITELIST; then
    if terraform plan -out "$PROJECT_NAME.plan" -var-file="cluster.tfvars"; then
        printf "Planned\n"
    else 
        printf "Could not plan infrastructure\n\nAborting\n\n"
        exit 1
    fi
}

createInfra() {
    planInfra
    printf "Terraforming\n"
    if terraform apply "$PROJECT_NAME.plan"; then
        printf "terraformed\n"
    else 
        printf "Could not terraform\n\nAborting\n\n"
        exit 1
    fi
}

case $1 in
    "plan")
    planInfra
    ;;
    "create")
    createInfra
    ;;
    "destroy")
    terraform destroy -auto-approve -var-file="cluster.tfvars"
    ;;
    "info")
    print
    ;;
    "token")
    kubectl get secret $(kubectl get serviceaccount admin-user -n kubernetes-dashboard -o jsonpath="{.secrets[0].name}") -o jsonpath="{.data.token}" -n kubernetes-dashboard | base64 --decode
    ;;
    *)
    help
    ;;
esac