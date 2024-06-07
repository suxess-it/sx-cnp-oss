# Onboarding teams and apps

According to the ADR [Onboarding teams in a gitops way](https://github.com/suxess-it/sx-cnp-oss/blob/main/backstage-resources/adr/0001-gitops-onboarding-teams.md) we are currently working with the approach [apps-in-any-namespace and multi-tenant kyverno-policies](https://github.com/suxess-it/sx-cnp-oss/blob/main/backstage-resources/adr/0001-gitops-onboarding-teams.md#apps-in-any-namespace-and-multi-tenant-kyverno-policies).

For detailed explanations how this approach works, please read through the ADR.

So here are the steps to onboard new teams in this approach:

## onboarding new teams

### add new team and configuration in argocd chart

add a new team in this [teams-array](https://github.com/suxess-it/sx-cnp-oss/blob/98f8990c888b60283f3c3f51ac19c505b71e8141/platform-apps/charts/argocd/values-k3d.yaml#L1-L18) with the corresponding attributes.

#### app-onboarding options
with [appOfAppsRepo](https://github.com/suxess-it/sx-cnp-oss/blob/98f8990c888b60283f3c3f51ac19c505b71e8141/platform-apps/charts/argocd/values-k3d.yaml#L13-L16) we define a gitops-repo where the dev-team can create its own application definitions. Still, it is automatically restricted that these applications can only belong to the teams argocd app-project.

with [multiStageKargoAppSet](https://github.com/suxess-it/sx-cnp-oss/blob/98f8990c888b60283f3c3f51ac19c505b71e8141/platform-apps/charts/argocd/values-k3d.yaml#L17C5-L18) and ApplicationSet is automatically created in the <team>-apps which constantly searches for corresponding gitops-repos and adds new applications automatically in the <team>-apps namespace. This special ApplicationSet creates an application per stage defined in an `app-stages.yaml` like this [example](https://github.com/suxess-it/team1-demo-app1/blob/main/app-stages.yaml) and adds kargo project, warehouse and stages to the cluster.

### add new app-definition namespace
add the name team app-definition namespace in [application.namespaces](https://github.com/suxess-it/sx-cnp-oss/blob/98f8990c888b60283f3c3f51ac19c505b71e8141/platform-apps/charts/argocd/values-k3d.yaml#L42) and [applicationsetcontroller.namespaces](https://github.com/suxess-it/sx-cnp-oss/blob/98f8990c888b60283f3c3f51ac19c505b71e8141/platform-apps/charts/argocd/values-k3d.yaml#L43).

### check if multi-tenant kyverno-policies get applied

we set them in [kyverno-policies array](https://github.com/suxess-it/sx-cnp-oss/blob/98f8990c888b60283f3c3f51ac19c505b71e8141/platform-apps/charts/kyverno/values.yaml#L1)

currently there is just a limitrange and resourcequota resource generated, networkpolicies and others will follow.

## onboarding new apps

As a dev-team you then can add new applications in different ways now depending on the knowledge and flexibility of your dev-team.

### one simple deployment-descriptor with appset and base-chart provided by platform-team automatically

tbd .. with an "all-in-one-flexible-helm-chart", an appset with multi-source app and a simple deployment-descriptor like https://github.com/jkleinlercher/just-one-yaml-deployment/blob/main/apps/my-aspnetapp/deployit.yaml you can automatically generate new apps.

### one simple deployment-descriptor for multi-stage app with kargo project

create an app like [team1-demo-app1](https://github.com/suxess-it/team1-demo-app1) with this [app-stages.yaml](https://github.com/suxess-it/team1-demo-app1/blob/main/app-stages.yaml) in it.

The repo organization must match the organization defined in the team-onboarding attribute "teams.[].multiStageKargoAppSet.organization" and the repo-name must start with the team name (e.g. team1-demo-app).

Then apps for each stage in the app-stage.yaml get created, and a corresponding kargo project, warehouse and stages which is responsible for git-promotion to production.

This approach does lots of things out-of-the-box and is good, as long as you are fine with the standards the ApplicationSet and the [Application-Helm-Chart](https://github.com/suxess-it/sx-cnp-oss/blob/main/team-apps/onboarding-apps-charts/multi-stage-app-with-kargo-pipeline/README.md#applicationset-with-scm-provider) define.

### use some platform helm-chart as a source for an applicationset

the same Application-Helm-Chart as in the option before can also be used directly in an ApplicationSet which the dev-team just creates in ins team-app-of-apps-repo, like https://github.com/suxess-it/team1-apps/blob/main/k3d-apps/example-multi-stage-app-with-kargo.yaml.

describe in
- https://github.com/suxess-it/sx-cnp-oss/blob/main/backstage-resources/adr/0002-gitops-onboarding-apps.md#applicationset-with-parent-helm-chart
- or in https://github.com/suxess-it/sx-cnp-oss/blob/main/backstage-resources/adr/0002-gitops-onboarding-apps.md#applicationset-with-configjson-representing-a-parent-helm-chart

### deploy applications as you want

just deploy an argocd app definition and other K8s resources in your [team-app-of-apps-repo](https://github.com/suxess-it/team1-apps/tree/main/k3d-apps) as defined in the team-onboarding attribute "teams.[].appOfAppsRepo".


## big picture

![image](https://github.com/suxess-it/sx-cnp-oss/assets/11465610/8edf7545-f95e-4404-b884-734a7a414bcf)




## more informations

just for testing:

kargo needs to write to your gitops repo to promote changed from one stage to another. in this demo we use the [suxess-it demo-app](https://github.com/suxess-it/sx-cnp-oss-demo-app). this needs to get customized for the team-apps and kargo projects above

```
export GITHUB_USERNAME=<your github handle>
export GITHUB_PAT=<your personal access token>
kubectl create secret generic git-demo-app -n kargo-demo-app --from-literal=repoURL=https://github.com/suxess-it/sx-cnp-oss-demo-app --from-literal=username=${GITHUB_USERNAME} --from-literal=password=${GITHUB_PAT}
kubectl label secret git-demo-app -n kargo-demo-app kargo.akuity.io/cred-type=git
```

URLs for stages (not true anymore):

- test: http://test-demo-app-127-0-0-1.nip.io
- qa: http://qa-demo-app-127-0-0-1.nip.io
- prod: http://prod-demo-app-127-0-0-1.nip.io