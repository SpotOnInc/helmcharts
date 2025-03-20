#!/usr/bin/env bash

##############################################################
# This script transitions a spoton-monochart deployment or statefulset to be
# ready for the spoton-monochart label updates. It does this
# by creating a temp resource, deleting the old resource,
# then creating a new resource with the updated labels.
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

check_release_is_monochart() {
  chart_and_version=$(helm history -n "$RELEASE_NAMESPACE" "$RELEASE_NAME" -o yaml | yq '.[-1].chart')
  if [[ "$chart_and_version" != spoton-monochart* ]]; then
    message "ℹ️ ${RELEASE_NAME} is not spoton-monochart. Skipping."
    exit 0
  fi
}

get_deployment() {
  helm_values=$(helm get values -n "$RELEASE_NAMESPACE" "$RELEASE_NAME")
  DEPLOYMENT=$(yq eval .fullnameOverride <<< "$helm_values")

  if [[ "$RESOURCE" == "null" ]]; then
    message "⚠️  Could not determine deployment name. Exiting."
    exit 1
  fi
}

RELEASE_NAME=$1
RELEASE_NAMESPACE=$2
echo
echo "************************************************************"
echo "[spoton-monochart labels update]"
echo
echo "RELEASE_NAMESPACE: ${RELEASE_NAMESPACE}"
echo "RELEASE_NAME: ${RELEASE_NAME}"
echo "************************************************************"

# Check if the required arguments are present
if [[ -z "$RELEASE_NAME" ]] || [[ -z "$RELEASE_NAMESPACE" ]]; then
  message '⚠️  Missing required arguments. Please provide the following:'
  message '    - RELEASE_NAME - e.g. monochart-testing-staging'
  message '    - RELEASE_NAMESPACE - e.g. staging'
  exit 1
fi

check_release_is_monochart
get_deployment
SERVICE="$RESOURCE"

echo "👷 Confirming that deployment or statefulset ${DEPLOYMENT} exists before continuing..."
resource_yaml=$(kubectl get deployment,statefulset -n "$RELEASE_NAMESPACE" "$RESOURCE" -o yaml --ignore-not-found 2>&1)
if [[ -z "$resource_yaml" ]] || [[ "$resource_yaml" =~ "not found" ]]; then
  echo "⚠️  The deployment or statefulset ${DEPLOYMENT} does not exist. Nothing to do for label changes. Skipping."
  exit 0
fi

label_app_name=$(yq eval .spec.template.metadata.labels.\"app.kubernetes.io/name\" <<< "$resource_yaml")
if [[ "$label_app_name" == "$RESOURCE" ]]; then
  echo "✅ Deployment or statefulset ${DEPLOYMENT} is already updated for monochart label changes."
  exit 0
else
  echo "ℹ️ Deployment or statefulset ${DEPLOYMENT} needs updating for monochart label changes."
fi

TEMP_DEPLOYMENT="${DEPLOYMENT}-temp"

echo
echo "DEPLOYMENT: ${DEPLOYMENT}"
echo "SERVICE: ${SERVICE}"
echo "TEMP_DEPLOYMENT: ${TEMP_DEPLOYMENT}"

# Create a temp resource (same except for the name)
message '👷 Creating temp resource...'
kubectl get deployment,statefulset -n "${RELEASE_NAMESPACE}" "${DEPLOYMENT}" -o yaml |
  yq eval ".metadata.name = \"${TEMP_DEPLOYMENT}\"" - \
    > "${TEMP_DEPLOYMENT}".resource.yaml

kubectl apply -f "${TEMP_DEPLOYMENT}".resource.yaml

# Wait for temp resource to finish
kubectl rollout status deployment,statefulset -n "${RELEASE_NAMESPACE}" "${TEMP_DEPLOYMENT}" -w --timeout=0s

message '👷 Deleting old resource...'
kubectl delete deployment,statefulset -n "${RELEASE_NAMESPACE}" "${DEPLOYMENT}"

message '👷 Creating new resource...'
# Using yq, update the yaml with the new labels and apply this as the replacement resource
kubectl get deployment,statefulset -n "$RELEASE_NAMESPACE" "${TEMP_DEPLOYMENT}" -o yaml |
  yq eval "
    (.metadata.name = \"${DEPLOYMENT}\") |
    (.spec.selector.matchLabels.\"app.kubernetes.io/name\"=\"${DEPLOYMENT}\") |
    (.spec.template.metadata.labels.\"app.kubernetes.io/name\"=\"${DEPLOYMENT}\")
  " - > "${DEPLOYMENT}".resource.yaml
kubectl apply -f "${DEPLOYMENT}".resource.yaml

# Wait for resource to finish
kubectl rollout status deployment,statefulset -n "${RELEASE_NAMESPACE}" "${DEPLOYMENT}" -w --timeout=0s

# Patch the service so that its matchLabels point to the new pods
service_yaml=$(kubectl get service -n "$RELEASE_NAMESPACE" "$SERVICE" -o yaml --ignore-not-found 2>&1)
if [[ -z "$service_yaml" ]] || [[ "$service_yaml" =~ "not found" ]]; then
  echo "⚠️  The service ${SERVICE} does not exist. Skipping service patch."
else
  kubectl patch service -n "$RELEASE_NAMESPACE" "$SERVICE" -p "{\"spec\": {\"selector\": {\"app.kubernetes.io/name\": \"${DEPLOYMENT}\"}}}"
fi

message '👷 Deleting temp resource...'
kubectl delete deployment,statefulset -n "${RELEASE_NAMESPACE}" "${TEMP_DEPLOYMENT}"

message '🏁 [spoton-monochart labels update] All done!'
