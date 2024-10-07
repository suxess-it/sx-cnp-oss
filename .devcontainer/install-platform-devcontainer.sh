#!/bin/bash
set -e  # Exit on non-zero exit code from commands

echo "$(date): Running post-start.sh" >> ~/.status.log

# Docker can take a couple seconds to come up. Wait for it to be ready before
# proceeding with bootstrap. https://github.com/devcontainers/features/issues/977#issuecomment-2148230117
iterations=10
while ! docker ps &>/dev/null; do
  if [[ $iterations -eq 0 ]]; then
    echo "Timeout waiting for the Docker daemon to start."
    exit 1
  fi

  iterations=$((iterations - 1))
  echo 'Docker is not ready. Waiting 10 seconds and trying again.'
  sleep 10
done

# fix for https://github.com/kubernetes-sigs/kind/issues/2488
# but using the microsoft devcontainer docker-in-docker image should also work,
# but I didn't find it
if [[ $( docker network ls | grep kind ) ]] ; then
  echo "kind network already exists"
else
  docker network create -d=bridge --subnet=172.19.0.0/24 kind
fi

# this runs in background each time the container starts
export CURRENT_BRANCH=$( git rev-parse --abbrev-ref HEAD )
if [ ${CODESPACES} ]; then
  export CURRENT_REPOSITORY=${GITHUB_REPOSITORY}
else
  export CURRENT_REPOSITORY=$( git config --get remote.origin.url | sed 's/^https:\/\/github.com\///g' | sed 's/.git$//g' )
fi
#export CREATE_K3D_CLUSTER=true

# install mkcert
if [ ! -x /usr/local/bin/mkcert ]; then
  curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
  chmod +x mkcert-v*-linux-amd64
  sudo mv mkcert-v*-linux-amd64 /usr/local/bin/mkcert
fi

# create kind cluster by ourselves
if [[ $( kind get clusters | grep devcontainer-cluster ) ]] ; then
  echo "kind cluster 'devcontainer-cluster' already exists"
  echo "wait 10 seconds for starting up ..."
  sleep 10
  echo "wait time over .."
  echo "export kubeconfig"
  kind export kubeconfig --name devcontainer-cluster
  echo "wait until KinD cluster is available"
  iterations=10
  while ! kubectl cluster-info &>/dev/null; do
    if [[ $iterations -eq 0 ]]; then
      echo "Timeout waiting for KinD cluster to start."
      exit 1
    fi
    iterations=$((iterations - 1))
    echo 'KinD cluster is not ready. Waiting 10 seconds and trying again.'
    sleep 10
  done
else
  kind create cluster --name devcontainer-cluster --config .devcontainer/kind-config.yaml
fi

# here we can add some NodePort objects if we want to open ports before the apps are installed

if [[ ${TARGET_TYPE} == "KIND-DELIVERY" ]] ; then
  kubectl create namespace kargo --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f .devcontainer/kargo-nodeport.yaml

elif  [[ ${TARGET_TYPE} == "KIND-OBSERVABILITY" ]] ; then
  kubectl create namespace grafana --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f .devcontainer/grafana-nodeport.yaml

elif  [[ ${TARGET_TYPE} == "KIND-SECURITY" ]] ; then
  kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f .devcontainer/keycloak-nodeport.yaml

  kubectl create namespace falco --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f .devcontainer/falco-nodeport.yaml
fi

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f .devcontainer/argocd-nodeport.yaml
kubectl create namespace backstage --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f .devcontainer/backstage-nodeport.yaml
kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f .devcontainer/keycloak-nodeport.yaml

./install-platform.sh

if [[ ${TARGET_TYPE} == "KIND-DELIVERY" ]] ; then
  echo "kubrix delivery is set up sucessfully."
  echo "Kargo url: https://${CODESPACE_NAME}-6689.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
  echo "Kargo password: admin"

elif  [[ ${TARGET_TYPE} == "KIND-OBSERVABILITY" ]] ; then
  echo "kubrix observability is set up sucessfully."
  echo "Grafana url: https://${CODESPACE_NAME}-6690.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
  echo "Grafana user: admin"
  echo "Grafana password: prom-operator"

elif  [[ ${TARGET_TYPE} == "KIND-PORTAL" ]] ; then
  echo "kubrix portal is set up sucessfully."
  echo "Backstage url: https://${CODESPACE_NAME}-6691.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
  echo "Keycloak url: https://${CODESPACE_NAME}-6692.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"

elif  [[ ${TARGET_TYPE} == "KIND-SECURITY" ]] ; then
  echo "kubrix portal is set up sucessfully."
  echo "Keycloak url: https://${CODESPACE_NAME}-6692.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
  echo "Falco url: https://${CODESPACE_NAME}-6693.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
fi

argocd_password=$( kubectl get secret -n argocd argocd-initial-admin-secret -o=jsonpath='{.data.password}' | base64 -d )
echo "ArgoCD url: https://${CODESPACE_NAME}-6688.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
echo "ArgoCD user: admin"
echo "ArgoCD password: ${argocd_password}"

echo "$(date): Finished post-start.sh" >> ~/.status.log
