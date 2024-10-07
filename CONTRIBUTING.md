# Build suXess backstage container image and push it to our registry

## automatically with Github Actions

Workflow-File: https://github.com/suxess-it/sx-backstage/blob/feat/cnp-local-demo-jokl/.github/workflows/ci.yaml

## manually on local machine
dual arch build, x86 and arm64, arm64 build could take up to 50 minutes 
```
git clone https://github.com/suxess-it/sx-backstage.git
cd sx-backstage
git switch feat/cnp-local-demo-jokl
# modify code, test, commit
docker build -t sx-backstage:latest .
docker tag sx-backstage:latest ghcr.io/suxess-it/sx-backstage:latest
docker push ghcr.io/suxess-it/sx-backstage:latest
kubectl rollout restart deploy/sx-backstage -n backstage
```
