#!/bin/bash
set -e

CLUSTER=aws.kazoku.co
ZONE=us-east-1
SUBNETS=(subnet-ab591c86 subnet-eb6943a2 subnet-1a088f26 subnet-d3413288)
SECGROUPS="--security-groups=sg-4bfa2037 --security-groups=sg-44fa2038"

FSID=$(aws --output=text --query=FileSystemId efs create-file-system --creation-token=$(openssl rand -hex 32))
echo "created: $FSID"

STATE="creating"
until [[ ${STATE} == "available" ]]; do
	echo "-- waiting (state=${STATE})"
	STATE=$(aws --output=text --query=FileSystems[0].LifeCycleState efs describe-file-systems --file-system-id=${FSID})
	sleep 1
done

aws efs create-tags --file-system-id=${FSID} --tags="Key=KubernetesCluster,Value=${CLUSTER}"

for subnet in ${SUBNETS[@]}; do
	aws efs --output=json create-mount-target --file-system-id=${FSID} --subnet-id=${subnet} ${SECGROUPS}
done

kubectl create -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${FSID}
  annotations:
    volume.beta.kubernetes.io/storage-class: "slow"
spec:
  capacity:
    storage: 1000Gi
  accessModes:
    - ReadWriteMany
    - ReadOnlyMany
  persistentVolumeReclaimPolicy: Recycle
  nfs:
    path: /
    server: ${FSID}.efs.${ZONE}.amazonaws.com
EOF
