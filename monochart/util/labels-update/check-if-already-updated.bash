#!/usr/bin/env bash

##############################################################
# This script checks if a deployment's labels have already
# been updated.
#
# The following positional arguments are required:
#   - RELEASE - e.g. monochart-testing
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
  message '    - RELEASE_NAME - e.g. monochart-testing'
  message '    - RELEASE_NAMESPACE - e.g. staging'
  exit 1
fi

helm_values=$(helm get values -n "$RELEASE_NAMESPACE" "$RELEASE_NAME")
DEPLOYMENT=$(yq eval .fullnameOverride <<< "$helm_values")
if [[ "$DEPLOYMENT" == "null" ]]; then
  message "⚠️  Could not determine deployment name. Exiting."
  exit 1
fi

echo "***********************************"
echo "RELEASE_NAMESPACE: ${RELEASE_NAMESPACE}"
echo "RELEASE_NAME: ${RELEASE_NAME}"
echo "DEPLOYMENT: ${DEPLOYMENT}"
echo "***********************************"

deployment_yaml=$(kubectl get deployment -n "$RELEASE_NAMESPACE" "$DEPLOYMENT" -o yaml 2>&1)
if [[ "$?" == 1 ]]; then
  if [[ "$deployment_yaml" =~ "not found" ]]; then
    echo "⚠️  The deployment ${DEPLOYMENT} does not exist."
    exit 1
  else
    echo "❗ There was an error checking the deployment: $deployment_yaml"
    exit 1
  fi
fi

label_app_name=$(yq eval .spec.template.metadata.labels.\"app.kubernetes.io/name\" <<< "$deployment_yaml")
if [[ "$label_app_name" == "$DEPLOYMENT" ]]; then
  echo "Already updated."
else
  echo "Needs updating."
fi
