#!/bin/bash

set -x

if [ "${TARGET_TYPE}" == "K3D" ] ; then
  # do we need to set this always? I had DNS issues on the train
  export K3D_FIX_DNS=1
  
  k3d cluster create cnp-local-demo \
    -p "80:80@loadbalancer" \
    -p "443:443@loadbalancer" \
    --k3s-arg '--cluster-init@server:0' \
    --k3s-arg '--etcd-expose-metrics=true@server:0' \
    --agents 2 \
    --wait
fi

if [ "${TARGET_TYPE}" == "K3D" ] || [ "${TARGET_TYPE}" == "KIND" ] ; then
# create mkcert certs in alle namespaces with ingress
for namespace in backstage kargo monitoring argocd keycloak kubecost falco; do
  kubectl create namespace ${namespace}
  # for grafana the namespace is not the same as the ingress hostname
  if [ "${namespace}" = "monitoring" ]; then
    mkcert -cert-file ${namespace}-cert.pem -key-file ${namespace}-key.pem grafana-127-0-0-1.nip.io
  else
    mkcert -cert-file ${namespace}-cert.pem -key-file ${namespace}-key.pem ${namespace}-127-0-0-1.nip.io
  fi
  # kargo needs a special secret name according to its helm chart
  if [ "${namespace}" = "kargo" ]; then
    kubectl create secret tls kargo-api-ingress-cert -n ${namespace} --cert=${namespace}-cert.pem --key=${namespace}-key.pem
  else
    kubectl create secret tls ${namespace}-server-tls -n ${namespace} --cert=${namespace}-cert.pem --key=${namespace}-key.pem
  fi
  rm ${namespace}-cert.pem ${namespace}-key.pem
done
fi

if [ "${TARGET_TYPE}" == "KIND" ] ; then
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=90s
fi

# create argocd with helm chart not with install.yaml
# because afterwards argocd is also managed by itself with the helm-chart

helm install sx-argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --version 7.1.3 \
  --namespace argocd \
  --create-namespace \
  --set configs.cm.application.resourceTrackingMethod=annotation \
  -f https://raw.githubusercontent.com/suxess-it/sx-cnp-oss/${CURRENT_BRANCH}/bootstrap-argocd-values.yaml \
  --wait

# create secret for scm applicationset in team app definition namespaces
# see https://github.com/suxess-it/sx-cnp-oss/issues/214 for a sustainable solution
for ns in adn-team1 adn-team2; do
  kubectl create namespace ${ns}
  kubectl create secret generic appset-github-token --from-literal=token=${GITHUB_APPSET_TOKEN} -n ${ns}
done

CURRENT_BRANCH_SED=$( echo ${CURRENT_BRANCH} | sed 's/\//\\\//g' )

# bootstrap-app
curl -L https://raw.githubusercontent.com/suxess-it/sx-cnp-oss/${CURRENT_BRANCH}/bootstrap-app-$(echo ${TARGET_TYPE} | awk '{print tolower($0)}').yaml | sed "s/targetRevision: main/targetRevision: ${CURRENT_BRANCH_SED}/g" | kubectl apply -n argocd -f -

# create app list
case "${TARGET_TYPE}" in
KIND)
  URL=https://raw.githubusercontent.com/suxess-it/sx-cnp-oss/${CURRENT_BRANCH}/platform-apps/target-chart/values-k3d.yaml
  argocd_apps=$(curl -L $URL | grep -v backstage | awk '/^  - name:/ { printf "%s", "sx-"$3" "}' )
;;
*)
  URL=https://raw.githubusercontent.com/suxess-it/sx-cnp-oss/${CURRENT_BRANCH}/platform-apps/target-chart/values-$(echo ${TARGET_TYPE} | awk '{print tolower($0)}').yaml
  argocd_apps=$(curl -L $URL | grep -v backstage | awk '/^  - name:/ { printf "%s", "sx-"$3" "}' )
;;
esac

# max wait for 20 minutes
end=$((SECONDS+1800))

all_apps_synced="true"
while [ $SECONDS -lt $end ]; do
  all_apps_synced="true"
  for app in ${argocd_apps} ; do
    kubectl get application -n argocd ${app} | grep "Synced.*Healthy"
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
      all_apps_synced="false"	
    fi
  done
  if [ ${all_apps_synced} = "true" ] ; then
    echo "${argocd_apps} apps are synced"
    break
  fi
  kubectl get application -n argocd
  echo "timer: $SECONDS"
  echo "end: $end"
  sleep 10
done

echo "status of all pods"
kubectl get pods -A
if [ ${all_apps_synced} != "true" ] ; then
  echo "not all apps synced and healthy after limit reached :("
  exit 1
else
  echo "all apps are synced. ready for take off :)"
fi

# apply argocd-secret to set a secretKey
kubectl apply -f https://raw.githubusercontent.com/suxess-it/sx-cnp-oss/${CURRENT_BRANCH}/platform-apps/charts/argocd/manual-secret/argocd-secret.yaml

# get hostnames
# gethostnames from ingress - to remove TARGET_TYPE 
export ARGOCD_HOSTNAME=$(kubectl get ingress -o jsonpath='{.items[*].spec.rules[*].host}' -n argocd)
export GRAFANA_HOSTNAME=$(kubectl get ingress -o jsonpath='{.items[*].spec.rules[*].host}' -n monitoring)

# download argocd
curl -kL -o argocd https://${ARGOCD_HOSTNAME}/download/argocd-linux-amd64
chmod u+x argocd

INITIAL_ARGOCD_PASSWORD=$( kubectl get secret -n argocd argocd-initial-admin-secret -o=jsonpath={'.data.password'} | base64 -d )
./argocd login ${ARGOCD_HOSTNAME} --grpc-web --insecure --username admin --password ${INITIAL_ARGOCD_PASSWORD}
export ARGOCD_AUTH_TOKEN="argocd.token=$( ./argocd account generate-token --account backstage --grpc-web )"

ID=$( curl -k -X POST https://${GRAFANA_HOSTNAME}/api/serviceaccounts --user 'admin:prom-operator' -H "Content-Type: application/json" -d '{"name": "backstage","role": "Viewer","isDisabled": false}' | jq -r .id )
export GRAFANA_TOKEN=$(curl -k -X POST https://${GRAFANA_HOSTNAME}/api/serviceaccounts/${ID}/tokens --user 'admin:prom-operator' -H "Content-Type: application/json" -d '{"name": "backstage"}' | jq -r .key)


# check if backstage is already synced (it will still be degraded because of the missing secret we create in the next step)
# max wait for 5 minutes
argocd_apps="sx-backstage"

end=$((SECONDS+300))

all_apps_synced="true"
while [ $SECONDS -lt $end ]; do
  all_apps_synced="true"
  for app in ${argocd_apps} ; do
    kubectl get application -n argocd ${app} | grep "Synced"
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
      all_apps_synced="false"
    fi
  done
  if [ ${all_apps_synced} = "true" ] ; then
    echo "${argocd_apps} apps are synced"
    break
  fi
  kubectl get application -n argocd
  echo "timer: $SECONDS"
  echo "end: $end"
  sleep 10
done



export K8S_SA_TOKEN=$( kubectl get secret backstage-locator -n backstage  -o jsonpath='{.data.token}' | base64 -d )

# create manual-secret secret with all tokens for backstage
kubectl create secret generic -n backstage manual-secret --from-literal=GITHUB_CLIENTSECRET=${GITHUB_CLIENTSECRET} --from-literal=GITHUB_CLIENTID=${GITHUB_CLIENTID} --from-literal=GITHUB_ORG=${GITHUB_ORG} --from-literal=GITHUB_TOKEN=${GITHUB_TOKEN} --from-literal=K8S_SA_TOKEN=${K8S_SA_TOKEN} --from-literal=ARGOCD_AUTH_TOKEN=${ARGOCD_AUTH_TOKEN} --from-literal=GRAFANA_TOKEN=${GRAFANA_TOKEN}

kubectl rollout restart deploy/sx-backstage -n backstage


# finally wait for all apps backstage included to be synced and health
argocd_apps=$(curl -L $URL | awk '/^  - name:/ { printf "%s", "sx-"$3" "}' )

# max wait for 20 minutes
end=$((SECONDS+300))

all_apps_synced="true"
while [ $SECONDS -lt $end ]; do
  all_apps_synced="true"
  for app in ${argocd_apps} ; do
    kubectl get application -n argocd ${app} | grep "Synced.*Healthy"
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
      all_apps_synced="false"	
    fi
  done
  if [ ${all_apps_synced} = "true" ] ; then
    echo "${argocd_apps} apps are synced"
    break
  fi
  kubectl get application -n argocd
  echo "timer: $SECONDS"
  echo "end: $end"
  sleep 10
done

echo "status of all pods"
kubectl get pods -A
if [ ${all_apps_synced} != "true" ] ; then
  echo "not all apps synced and healthy after limit reached :("
  exit 1
else
  echo "all apps are synced. ready for take off :)"
fi
