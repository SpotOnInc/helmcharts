#!/usr/bin/env bash

##############################################################
# This script transitions a spoton-monochart deployment to be
# ready for the spoton-monochart label updates. It does this
# by creating a temp deployment, deleting the old deployment,
# then creating a new deployment with the updated labels.
#
# The following positional arguments are required:
#   - RELEASE_NAME - e.g. monochart-testing-staging
#   - RELEASE_NAMESPACE - e.g. staging
##############################################################

set -eo pipefail

message() {
  echo
  echo "$1"
  echo
}

RELEASE_NAME=$1
RELEASE_NAMESPACE=$2

# Check if the required arguments are present
if [[ -z "$RELEASE_NAME" ]] || [[ -z "$RELEASE_NAMESPACE" ]]; then
  message '⚠️  Missing required arguments. Please provide the following:'
  message '    - RELEASE_NAME - e.g. monochart-testing-staging'
  message '    - RELEASE_NAMESPACE - e.g. staging'
  exit 1
fi

helm_values=$(helm get values -n "$RELEASE_NAMESPACE" "$RELEASE_NAME")
DEPLOYMENT=$(yq eval .fullnameOverride <<< "$helm_values")
SERVICE="$DEPLOYMENT"
if [[ "$DEPLOYMENT" == "null" ]]; then
  message "⚠️  Could not determine deployment name. Exiting."
  exit 1
fi

echo "👷 Confirming that deployment ${DEPLOYMENT} exists before continuing..."
check_deployment=$(kubectl get deployment -n "$RELEASE_NAMESPACE" "$DEPLOYMENT" -o yaml 2>&1)
if [[ "$?" == 1 ]]; then
  if [[ "$check_deployment" =~ "not found" ]]; then
    echo "⚠️  The deployment ${DEPLOYMENT} does not exist. Skipping."
    exit 0
  else
    echo "❗ There was an error checking the deployment: $check_deployment"
    exit 1
  fi
fi

TEMP_DEPLOYMENT="${DEPLOYMENT}-temp"

echo "***********************************"
echo "RELEASE_NAMESPACE: ${RELEASE_NAMESPACE}"
echo "RELEASE_NAME: ${RELEASE_NAME}"
echo "DEPLOYMENT: ${DEPLOYMENT}"
echo "SERVICE: ${SERVICE}"
echo "TEMP_DEPLOYMENT: ${TEMP_DEPLOYMENT}"
echo "***********************************"

# Create a temp deployment (same except for the name)
message '👷 Creating temp deployment...'
kubectl get deployment -n "${RELEASE_NAMESPACE}" "${DEPLOYMENT}" -o yaml |
  yq eval ".metadata.name = \"${TEMP_DEPLOYMENT}\"" - \
    > "${TEMP_DEPLOYMENT}".deployment.yaml

kubectl apply -f "${TEMP_DEPLOYMENT}".deployment.yaml

# Wait for temp deployment to finish
kubectl rollout status deployment -n "${RELEASE_NAMESPACE}" "${TEMP_DEPLOYMENT}" -w --timeout=0s

message '👷 Deleting old deployment...'
kubectl delete deployment -n "${RELEASE_NAMESPACE}" "${DEPLOYMENT}"

message '👷 Creating new deployment...'
# Using yq, update the yaml with the new labels and apply this as the replacement deployment
kubectl get deployment -n "$RELEASE_NAMESPACE" "${TEMP_DEPLOYMENT}" -o yaml |
  yq eval "
    (.metadata.name = \"${DEPLOYMENT}\") |
    (.spec.selector.matchLabels.\"app.kubernetes.io/name\"=\"${DEPLOYMENT}\") |
    (.spec.template.metadata.labels.\"app.kubernetes.io/name\"=\"${DEPLOYMENT}\")
  " - > "${DEPLOYMENT}".deployment.yaml
kubectl apply -f "${DEPLOYMENT}".deployment.yaml

# Wait for deployment to finish
kubectl rollout status deployment -n "${RELEASE_NAMESPACE}" "${DEPLOYMENT}" -w --timeout=0s

# Patch the service so that its matchLabels point to the new pods
kubectl patch service -n "$RELEASE_NAMESPACE" "$SERVICE" -p "{\"spec\": {\"selector\": {\"app.kubernetes.io/name\": \"${DEPLOYMENT}\"}}}"

message '👷 Deleting temp deployment...'
kubectl delete deployment -n "${RELEASE_NAMESPACE}" "${TEMP_DEPLOYMENT}"

message '🏁 All done!'
