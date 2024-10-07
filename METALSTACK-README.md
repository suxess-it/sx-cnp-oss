# SX-CNP on Metalstack

## how to set it up

### prereqs

#### aws route53 credentials

if you manage your DNS-Names in AWS Route53 with external-dns:
create IAM policy on AWS for AWS Route53: https://kubernetes-sigs.github.io/external-dns/v0.14.1/tutorials/aws/#iam-policy

then create User and static credentials based on https://kubernetes-sigs.github.io/external-dns/v0.14.1/tutorials/aws/#static-credentials
#TODO: i created the user in console, because I was too confused with logging into with aws cli. I need to understand and document this.

create a file `credentials` where "Access key" and "Secret access key" are stored like this:

```
[default]
aws_access_key_id = <access key>
aws_secret_access_key = <secret access key>
```

#### letsencrypt staging root certs

Currently we issue our certificates automatically with letsencrypt. However, due to some limits we don't use the production but the staging letsencrypt API. So you need to put those two root certs in your truststore: https://letsencrypt.org/docs/staging-environment/#root-certificates

#### create OAuth App in your Github Organization for Backstage login: https://backstage.io/docs/auth/github/provider/

- Homepage URL: https://portal-metalstack.platform-engineer.cloud/
- Authorization callback URL: https://portal-metalstack.platform-engineer.cloud/

use GITHUB_CLIENTSECRET and GITHUB_CLIENTID from your Github OAuth App for the following environment variables in step 3

### 1. create metalstack cluster

Create a K8s cluster on https://console.metalstack.cloud/, copy the KUBECONFIG to your local machine to `~/.kube/metalstack-config ` and set the KUBECONFIG to this file.

```
export KUBECONFIG=~/.kube/metalstack-config 
```

### 2. create AWS secret for external-dns 
create namespace and secret and delete local credentials file for security reasons:
```
kubectl create ns external-dns
kubectl create secret generic -n external-dns sx-external-dns --from-file credentials
rm credentials
```

### 3. define some variables so the platform can access github

```
export GITHUB_CLIENTSECRET=<value from steps above>
export GITHUB_CLIENTID=<value from steps above>
export GITHUB_TOKEN=<your personal access token>
export GITHUB_APPSET_TOKEN=<github-pat-for-argocd-appsets-only-read-permissions-needed>
```

### 4. install platform on metalstack cluster

```
export TARGET_TYPE=METALSTACK
# if you want to test another branch, specify something else than main
export CURRENT_BRANCH=main
curl -L https://raw.githubusercontent.com/suxess-it/sx-cnp-oss/${CURRENT_BRANCH}/install-platform.sh | bash
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

### 5. log in to the tools

| Tool    | URL | Username | Password |
| -------- | ------- | ------- | ------- |
| Backstage  | https://portal-metalstack.platform-engineer.cloud/  | via github | via github |
| ArgoCD | https://argocd-metalstack.platform-engineer.cloud/ | admin | `kubectl get secret -n argocd argocd-initial-admin-secret -o=jsonpath='{.data.password}' \| base64 -d` |
| Kargo | https://kargo-metalstack.platform-engineer.cloud/     | admin | - |
| Grafana    | https://grafana-metalstack.platform-engineer.cloud/   | admin | prom-operator |
| Kubevirt-Manager    | https://kubevirt-manager-metalstack.platform-engineer.cloud/   | - | - |

### 6. Onboard teams and applications

In our [Onboarding-Documentation](https://github.com/suxess-it/sx-cnp-oss/blob/main/backstage-resources/docs/ONBOARDING.md) we explain how new teams and apps get onboarded on the platform in a gitops way.

### 7. Promote apps with Kargo

tbd

# Troubleshooting

If argocd ingress is not working, use port-forwarding for accessing argocd console and investigate what is wrong
```
kubectl port-forward svc/sx-argocd-server -n argocd 8080:80
```

- Username: `admin`
- Password: `kubectl get secret -n argocd argocd-initial-admin-secret -o=jsonpath='{.data.password}' | base64 -d`

# AWS helpful things (DRAFT.)

install aws cli:
```
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install -i ~/bin/aws-cli -b ~/bin
rm -rf aws
rm -rf awscliv2.zip
```
configure aws cli: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-quickstart.html

create IAM policy:
```
aws iam create-policy --policy-name "AllowExternalDNSUpdates" --policy-document file://aws-resources/route53-iam-policy.json
```


# Tests

this ist just a test
something from suXess upstream

and something new

new change in upstream repo
