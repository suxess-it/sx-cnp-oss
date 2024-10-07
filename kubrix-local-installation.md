# Create a kubriX test environment on your local machine

## prereqs

k3d installed
kubectl installed

### mkcert

```
curl -L -O https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-amd64
mv mkcert-v1.4.4-linux-amd64 ~/bin/mkcert
chmod u+x ~/bin/mkcert
```

install the CA of mkcert in your OS truststore: https://docs.kubefirst.io/k3d/quick-start/install#install-the-ca-certificate-authority-of-mkcert-in-your-trusted-store

### create GitHub OAuth App 

in your Github Organization for Backstage login: https://backstage.io/docs/auth/github/provider/

- Homepage URL: https://backstage-127-0-0-1.nip.io
- Authorization callback URL: https://backstage-127-0-0-1.nip.io/api/auth/github

use GITHUB_CLIENTSECRET and GITHUB_CLIENTID from your Github OAuth App for the following environment variables in step 1

## 1. define some variables for the installation

For the installation some variables are needed:

```
export KUBRIX_GITHUB_CLIENTSECRET=<value from steps above>
export KUBRIX_GITHUB_CLIENTID=<value from steps above>
export KUBRIX_GITHUB_TOKEN=<your personal access token>
export KUBRIX_GITHUB_APPSET_TOKEN=<github-pat-for-argocd-appsets-only-read-permissions-needed>
# set target type to the platform stack you want to install
export TARGET_TYPE=KIND-DELIVERY
# if a K3d cluster should get created:
export CREATE_K3D_CLUSTER=true
# if you want to test another branch, specify something else than main
export CURRENT_BRANCH=main
# set the current repository to the origin or to your fork
export CURRENT_REPOSITORY=suxess-it/sx-cnp-oss
```

## 2. install platform-stack

```
curl -L https://raw.githubusercontent.com/${CURRENT_REPOSITORY}/${CURRENT_BRANCH}/install-platform.sh | bash
```

With this command a new k3d cluster gets created.
A "bootstrap argocd" get's installed via helm.
A "boostrap-app" gets installed which references all other apps in the plattform-stack (app-of-apps pattern)
ArgoCD itself is also then managed by an argocd app.

The platform stack will be installed automagically ;)

* backstage
* argocd (managed by argocd)
* argo-rollouts
* kargo
* cert-manager
* crossplane
* kyverno
* prometheus
* grafana
* promtail
* loki
* tempo
* kubecost
* keycloak
* external-secret-operator
* falco

## 3. log in to the tools

| Tool    | URL | Username | Password |
| -------- | ------- | ------- | ------- |
| Backstage  | https://backstage-127-0-0-1.nip.io | via github | via github |
| ArgoCD | https://argocd-127-0-0-1.nip.io/ | admin | `kubectl get secret -n argocd argocd-initial-admin-secret -o=jsonpath='{.data.password}' \| base64 -d` |
| Kargo | https://kargo-127-0-0-1.nip.io     | admin | - |
| Grafana    | https://grafana-127-0-0-1.nip.io | admin | prom-operator |
| Keycloak    | https://keycloak-127-0-0-1.nip.io | admin | admin |
| FalcoUI    | https://falco-127-0-0-1.nip.io | admin | admin |

## 4. kubecost

initialization need some minutes until values are visible in UI - https://kubecost-127-0-0-1.nip.io/overview

## 5. keycloak

depending on your hardware it needs some minutes until keycloak is running 

## 6. Onboard teams and applications

In our [Onboarding-Documentation](https://github.com/suxess-it/sx-cnp-oss/blob/main/backstage-resources/docs/ONBOARDING.md) we explain how new teams and apps get onboarded on the platform in a gitops way.

## 7. Promote apps with Kargo

tbd

## delete k3d cluster

```
k3d cluster stop cnp-local-demo
k3d cluster delete cnp-local-demo
```
