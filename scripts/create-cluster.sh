#!/bin/bash
set -e

# Variables (à adapter)
CLUSTER_NAME="mon-cluster"
REGION="ca-central-1"
NODEGROUP_NAME="standard-workers"
NODE_TYPE="t3.medium"
NODES=2
MIN_NODES=1
MAX_NODES=3
ROLE_NAME="AmazonEKSNodeRole"

echo "Création du rôle IAM pour les nœuds EKS : $ROLE_NAME"

# Créer fichier trust policy temporaire
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Créer le rôle IAM (ignore si existe déjà)
aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document file://trust-policy.json || echo "Le rôle existe déjà, on continue..."

# Attacher les politiques nécessaires
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess

# Nettoyer fichier temporaire
rm trust-policy.json

# Récupérer l'ARN du rôle
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
echo "ARN du rôle IAM : $ROLE_ARN"

echo "Génération du fichier de configuration eksctl..."

cat > cluster-config.yaml <<EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: $CLUSTER_NAME
  region: $REGION

managedNodeGroups:
  - name: $NODEGROUP_NAME
    instanceType: $NODE_TYPE
    desiredCapacity: $NODES
    minSize: $MIN_NODES
    maxSize: $MAX_NODES
    iam:
      instanceRoleARN: $ROLE_ARN
EOF

echo "Création du cluster EKS avec eksctl..."

eksctl create cluster -f cluster-config.yaml

echo "Mise à jour du kubeconfig..."

aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

echo "Vérification des nœuds du cluster..."

kubectl get nodes

echo "Cluster EKS prêt à l'emploi."

