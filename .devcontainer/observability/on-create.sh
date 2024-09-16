#!/bin/bash
set -e  # Exit on non-zero exit code from commands

echo "$(date): Running post-start.sh" >> ~/.status.log

# this runs in background each time the container starts

export GITHUB_CLIENTSECRET=dummy
export GITHUB_CLIENTID=dummy
export GITHUB_TOKEN=dummy
export GITHUB_APPSET_TOKEN=dummy
export TARGET_TYPE=KIND-OBSERVABILITY
export CURRENT_BRANCH=$( git rev-parse --abbrev-ref HEAD )
export CREATE_K3D_CLUSTER=true

# install mkcert
curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
chmod +x mkcert-v*-linux-amd64
sudo mv mkcert-v*-linux-amd64 /usr/local/bin/mkcert

# kind create cluster --name devcontainer-cluster --config=.github/kind-config.yaml

k3d cluster list

# Ensure kubeconfig is set up. 
# k3d kubeconfig merge dev --kubeconfig-merge-default

./install-platform.sh

echo "$(date): Finished post-start.sh" >> ~/.status.log
