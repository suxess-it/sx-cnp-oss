#!/bin/bash

set -x

if [ "${CREATE_K3D_CLUSTER}" == true ] ; then
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

if [[ "${TARGET_TYPE}" =~ ^KIND.* ]] ; then
  # create mkcert certs in alle namespaces with ingress
  for namespace in backstage kargo grafana argocd keycloak komoplane kubecost falco minio velero velero-ui vault; do
    kubectl create namespace ${namespace}
    mkcert -cert-file ${namespace}-cert.pem -key-file ${namespace}-key.pem ${namespace}-127-0-0-1.nip.io
    # kargo needs a special secret name according to its helm chart
    if [ "${namespace}" = "kargo" ]; then
      kubectl create secret tls kargo-api-ingress-cert -n ${namespace} --cert=${namespace}-cert.pem --key=${namespace}-key.pem
    else
      kubectl create secret tls ${namespace}-server-tls -n ${namespace} --cert=${namespace}-cert.pem --key=${namespace}-key.pem
    fi
    # minioconsole needs additional secret
    if [ "${namespace}" = "minio" ]; then
      mkcert -cert-file ${namespace}-console-cert.pem -key-file ${namespace}-console-key.pem minio-console-127-0-0-1.nip.io
      kubectl create secret tls minio-console-tls -n ${namespace} --cert=${namespace}-console-cert.pem --key=${namespace}-console-key.pem
      rm ${namespace}-console-cert.pem ${namespace}-console-key.pem
    fi
    rm ${namespace}-cert.pem ${namespace}-key.pem
  done

  # do not install kind nginx-controller and metrics-server on k3d cluster
  # since kind nginx only works on kind cluster and metrics-server is already installed on k3d
  if [[ ${CREATE_K3D_CLUSTER} != true ]] ; then
    # and install nginx ingress-controller
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
    kubectl wait --namespace ingress-nginx \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=90s

    helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
    helm repo update
    helm upgrade --install --set args={--kubelet-insecure-tls} metrics-server metrics-server/metrics-server --namespace kube-system
  fi
fi

# create argocd with helm chart not with install.yaml
# because afterwards argocd is also managed by itself with the helm-chart

helm install sx-argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --version 7.1.3 \
  --namespace argocd \
  --create-namespace \
  --set configs.cm.application.resourceTrackingMethod=annotation \
  -f https://raw.githubusercontent.com/${CURRENT_REPOSITORY}/${CURRENT_BRANCH}/bootstrap-argocd-values.yaml \
  --wait

# create secret for scm applicationset in team app definition namespaces
# see https://github.com/suxess-it/sx-cnp-oss/issues/214 for a sustainable solution
#for ns in adn-team1 adn-team2 adn-team-a; do
#  kubectl create namespace ${ns}
#  kubectl create secret generic appset-github-token --from-literal=token=${KUBRIX_GITHUB_APPSET_TOKEN} -n ${ns}
#done

CURRENT_BRANCH_SED=$( echo ${CURRENT_BRANCH} | sed 's/\//\\\//g' )
CURRENT_REPOSITORY_SED=$( echo ${CURRENT_REPOSITORY} | sed 's/\//\\\//g' )

# bootstrap-app
curl -L https://raw.githubusercontent.com/${CURRENT_REPOSITORY}/${CURRENT_BRANCH}/bootstrap-app-$(echo ${TARGET_TYPE} | awk '{print tolower($0)}').yaml | sed "s/targetRevision: main/targetRevision: ${CURRENT_BRANCH_SED}/g" | sed "s/suxess-it\/sx-cnp-oss/${CURRENT_REPOSITORY_SED}/g" | kubectl apply -n argocd -f -

# create app list
URL=https://raw.githubusercontent.com/${CURRENT_REPOSITORY}/${CURRENT_BRANCH}/platform-apps/target-chart/values-$(echo ${TARGET_TYPE} | awk '{print tolower($0)}').yaml

argocd_apps=$(curl -L $URL | awk '/^  - name:/ { printf "%s", "sx-"$3" "}' )
# list apps which need some sort of special treatment in bootstrap
argocd_apps_without_individual=$(curl -L $URL | egrep -Ev "backstage|kargo" | awk '/^  - name:/ { printf "%s", "sx-"$3" "}' )

# max wait for 20 minutes
max_wait_time=1200
start=$SECONDS
end=$((SECONDS+${max_wait_time}))

all_apps_synced="true"
while [ $SECONDS -lt $end ]; do
  all_apps_synced="true"
  for app in ${argocd_apps_without_individual} ; do
    kubectl get application -n argocd ${app} | grep "Synced.*Healthy"
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
      all_apps_synced="false"	
    fi
  done
  if [ ${all_apps_synced} = "true" ] ; then
    echo "${argocd_apps_without_individual} apps are synced"
    break
  fi
  kubectl get application -n argocd
  elapsed_time=$((SECONDS-${start}))
  echo "elapsed time: ${elapsed_time} seconds"
  echo "max wait time: ${max_wait_time} seconds"
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
kubectl apply -f https://raw.githubusercontent.com/${CURRENT_REPOSITORY}/${CURRENT_BRANCH}/platform-apps/charts/argocd/manual-secret/argocd-secret.yaml

# if kargo is part of this stack, upload token to vault
if [[ $( echo $argocd_apps | grep sx-kargo ) ]] ; then
  echo "adding special configuration for sx-kargo"
  export VAULT_HOSTNAME=$(kubectl get ingress -o jsonpath='{.items[*].spec.rules[*].host}' -n vault)
  curl -k --header "X-Vault-Token:$(kubectl get secret -n vault vault-init -o=jsonpath='{.data.root_token}'  | base64 -d)" --request POST --data "{\"data\": {\"GITHUB_APPSET_PAT\": \"$VAULT_TOKEN\", \"GITHUB_TOKEN\": \"$VAULT_TOKEN\", \"GITHUB_USERNAME\": \"jkleinlercher\"}}" https://${VAULT_HOSTNAME}/v1/sx-cnp-oss-kv/data/demo/delivery
  sleep 10
  kubectl delete ExternalSecret github-creds -n kargo
  # check if kargo is already synced 
  # max wait for 5 minutes
  argocd_app_individual="sx-kargo"

  max_wait_time=900
  start=$SECONDS
  end=$((SECONDS+${max_wait_time}))

  all_apps_synced="true"
  while [ $SECONDS -lt $end ]; do
    all_apps_synced="true"
    for app in ${argocd_app_individual} ; do
      kubectl get application -n argocd ${app} | grep "Synced.*Healthy"
      exit_code=$?
      if [[ $exit_code -ne 0 ]]; then
        all_apps_synced="false"
      fi
    done
    if [ ${all_apps_synced} = "true" ] ; then
      echo "${argocd_app_individual} apps are synced"
      break
    fi
    kubectl get application -n argocd
    elapsed_time=$((SECONDS-${start}))
    echo "elapsed time: ${elapsed_time} seconds"
    echo "max wait time: ${max_wait_time} seconds"
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
fi

# if backstage is part of this stack, create the manual secret for backstage
if [[ $( echo $argocd_apps | grep sx-backstage ) ]] ; then
echo "adding special configuration for sx-backstage"
  # get hostnames
  # gethostnames from ingress - to remove TARGET_TYPE 
  export ARGOCD_HOSTNAME=$(kubectl get ingress -o jsonpath='{.items[*].spec.rules[*].host}' -n argocd)
  export GRAFANA_HOSTNAME=$(kubectl get ingress -o jsonpath='{.items[*].spec.rules[*].host}' -n grafana)

  # download argocd
  curl -kL -o argocd https://${ARGOCD_HOSTNAME}/download/argocd-linux-amd64
  chmod u+x argocd

  INITIAL_ARGOCD_PASSWORD=$( kubectl get secret -n argocd argocd-initial-admin-secret -o=jsonpath={'.data.password'} | base64 -d )
  ./argocd login ${ARGOCD_HOSTNAME} --grpc-web --insecure --username admin --password ${INITIAL_ARGOCD_PASSWORD}
  export ARGOCD_AUTH_TOKEN="$( ./argocd account generate-token --account backstage --grpc-web )"
  rm argocd
  
  ID=$( curl -k -X POST https://${GRAFANA_HOSTNAME}/api/serviceaccounts --user 'admin:prom-operator' -H "Content-Type: application/json" -d '{"name": "backstage","role": "Viewer","isDisabled": false}' | jq -r .id )
  export GRAFANA_TOKEN=$(curl -k -X POST https://${GRAFANA_HOSTNAME}/api/serviceaccounts/${ID}/tokens --user 'admin:prom-operator' -H "Content-Type: application/json" -d '{"name": "backstage"}' | jq -r .key)

  # check if backstage is already synced (it will still be degraded because of the missing secret we create in the next step)
  # max wait for 5 minutes
  argocd_app_individual="sx-backstage"

  max_wait_time=900
  start=$SECONDS
  end=$((SECONDS+${max_wait_time}))

  all_apps_synced="true"
  while [ $SECONDS -lt $end ]; do
    all_apps_synced="true"
    for app in ${argocd_app_individual} ; do
      kubectl get application -n argocd ${app} | grep "Synced.*"
      exit_code=$?
      if [[ $exit_code -ne 0 ]]; then
        all_apps_synced="false"
      fi
    done
    if [ ${all_apps_synced} = "true" ] ; then
      echo "${argocd_app_individual} apps are synced"
      break
    fi
    kubectl get application -n argocd
    elapsed_time=$((SECONDS-${start}))
    echo "elapsed time: ${elapsed_time} seconds"
    echo "max wait time: ${max_wait_time} seconds"
    sleep 10
  done

  # get backstage-locator token for backstage secret
  export K8S_SA_TOKEN=$( kubectl get secret backstage-locator -n backstage  -o jsonpath='{.data.token}' | base64 -d )

  # create manual-secret secret with all tokens for backstage
  # in github codespace we need additional environment variables to overwrite app-config.yaml
  if [ ${CODESPACES} ]; then
    KEYCLOAK_CODESPACES=""
    GITHUB_CODESPACES="true"
    BACKSTAGE_CODESPACE_URL="https://${CODESPACE_NAME}-6691.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
  fi
  if [ ${KEYCLOAK_CODESPACES} ]; then
    kubectl create secret generic -n backstage manual-secret \
      --from-literal=GITHUB_CLIENTSECRET=${KUBRIX_GITHUB_CLIENTSECRET} \
      --from-literal=GITHUB_CLIENTID=${KUBRIX_GITHUB_CLIENTID} \
      --from-literal=GITHUB_ORG=${GITHUB_ORG} \
      --from-literal=GITHUB_TOKEN=${KUBRIX_GITHUB_TOKEN} \
      --from-literal=K8S_SA_TOKEN=${K8S_SA_TOKEN} \
      --from-literal=ARGOCD_AUTH_TOKEN=${ARGOCD_AUTH_TOKEN} \
      --from-literal=GRAFANA_TOKEN=${GRAFANA_TOKEN} \
      --from-literal=APP_CONFIG_app_baseUrl=${BACKSTAGE_CODESPACE_URL} \
      --from-literal=APP_CONFIG_backend_baseUrl=${BACKSTAGE_CODESPACE_URL} \
      --from-literal=APP_CONFIG_backend_cors_origin=${BACKSTAGE_CODESPACE_URL} \
      --from-literal=APP_CONFIG_auth_providers_oidc_development_callbackUrl=${BACKSTAGE_CODESPACE_URL}/api/auth/oidc/handler/frame \
      --from-literal=APP_CONFIG_auth_providers_oidc_development_clientId=backstage-codespaces \
      --from-literal=APP_CONFIG_auth_providers_oidc_development_metadataUrl=http://keycloak-service.keycloak.svc.cluster.local:8080/realms/sx-cnp-oss-codespaces \
      --from-literal=APP_CONFIG_auth_provider_github_development_callbackUrl=${BACKSTAGE_CODESPACE_URL}/api/auth/github/handler/frame \
      --from-literal=APP_CONFIG_catalog_providers_keycloakOrg_default_loginRealm=sx-cnp-oss-codespaces \
      --from-literal=APP_CONFIG_catalog_providers_keycloakOrg_default_realm=sx-cnp-oss-codespaces \
      --from-literal=APP_CONFIG_catalog_providers_keycloakOrg_default_clientId=backstage-codespaces \
      --from-literal=APP_CONFIG_catalog_providers_keycloakOrg_default_clientSecret=demosecret

  elif [ ${GITHUB_CODESPACES} ]; then
    kubectl create secret generic -n backstage manual-secret \
    --from-literal=GITHUB_CLIENTSECRET=${KUBRIX_GITHUB_CLIENTSECRET} \
    --from-literal=GITHUB_CLIENTID=${KUBRIX_GITHUB_CLIENTID} \
    --from-literal=GITHUB_ORG=${GITHUB_ORG} \
    --from-literal=GITHUB_TOKEN=${KUBRIX_GITHUB_TOKEN} \
    --from-literal=K8S_SA_TOKEN=${K8S_SA_TOKEN} \
    --from-literal=ARGOCD_AUTH_TOKEN=${ARGOCD_AUTH_TOKEN} \
    --from-literal=GRAFANA_TOKEN=${GRAFANA_TOKEN} \
    --from-literal=APP_CONFIG_app_baseUrl=${BACKSTAGE_CODESPACE_URL} \
    --from-literal=APP_CONFIG_backend_baseUrl=${BACKSTAGE_CODESPACE_URL} \
    --from-literal=APP_CONFIG_backend_cors_origin=${BACKSTAGE_CODESPACE_URL} \
    --from-literal=APP_CONFIG_auth_provider_github_development_callbackUrl=${BACKSTAGE_CODESPACE_URL}/api/auth/github/handler/frame

  else
    kubectl create secret generic -n backstage manual-secret \
    --from-literal=GITHUB_CLIENTSECRET=${KUBRIX_GITHUB_CLIENTSECRET} \
    --from-literal=GITHUB_CLIENTID=${KUBRIX_GITHUB_CLIENTID} \
    --from-literal=GITHUB_ORG=${GITHUB_ORG} \
    --from-literal=GITHUB_TOKEN=${KUBRIX_GITHUB_TOKEN} \
    --from-literal=K8S_SA_TOKEN=${K8S_SA_TOKEN} \
    --from-literal=ARGOCD_AUTH_TOKEN=${ARGOCD_AUTH_TOKEN} \
    --from-literal=GRAFANA_TOKEN=${GRAFANA_TOKEN}
  fi

  # in codespaces we need additional crossplane resources for keycloak
  # because of the port-forwarding URLs
  if [ ${KEYCLOAK_CODESPACES} ]; then
    curl -L https://raw.githubusercontent.com/${CURRENT_REPOSITORY}/${CURRENT_BRANCH}/.devcontainer/keycloak-codespaces.yaml | sed "s/BACKSTAGE_CODESPACES_REPLACE/${CODESPACE_NAME}-6691.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}/g" | sed "s/KEYCLOAK_CODESPACES_REPLACE/${CODESPACE_NAME}-6692.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}/g" | kubectl apply -n keycloak -f -
  fi

  # finally wait for all apps including backstage to be synced and health

  max_wait_time=300
  start=$SECONDS
  end=$((SECONDS+${max_wait_time}))

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
    elapsed_time=$((SECONDS-${start}))
    echo "elapsed time: ${elapsed_time} seconds"
    echo "max wait time: ${max_wait_time} seconds"
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
fi
