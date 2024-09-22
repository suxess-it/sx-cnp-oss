In this document are some runbooks for different problems listet.

## per-user series limit of 150000 exceeded (err-mimir-max-series-per-user)

When ingesting prometheus metrics to mimir you get the error `per-user series limit of 150000 exceeded (err-mimir-max-series-per-user)`.
Mimir has a configured limit of time series of 150k. This is on purpose because a higher number of time series could decrease performance and memory usage.
So before increasing the configured limit, you should take a look if your high series count is really needed.

Follow the steps in https://medium.com/@dotdc/how-to-find-unused-prometheus-metrics-using-mimirtool-a44560173543 to get all used and unused metrics in your environment.
Then follow https://medium.com/@dotdc/prometheus-performance-and-cardinality-in-practice-74d5d9cd6230 to drop unused metrics or increase the limit in the values:

```
  mimir:
    structuredConfig:
      limits:
        max_global_series_per_user: 500000
```

## write to WAL - no space left on device

mimir ingester pods log warnings concerning full WAL filesystem:

```
kubectl logs sx-mimir-ingester-zone-c-0 -n mimir

ts=2024-08-12T06:25:31.119841738Z caller=grpc_logging.go:76 level=warn method=/cortex.Ingester/Push duration=4.881001ms msg=gRPC err="user=gardener: write to WAL: log samples: write /data/tsdb/gardener/wal/00000727: no space left on device"
```

see https://community.grafana.com/t/mimir-ingesters-failing-on-no-space-left-on-device/66493/2

solution: increase ingester persistentVolume in values file, like https://github.com/grafana/mimir/blob/fefa35e43bcc36c58f8baa3b1de0171b5f590b28/operations/helm/charts/mimir-distributed/capped-small.yaml#L62C3-L63

example:

```
  ingester:
    persistentVolume:
      size: 50Gi
```

When increasing the PVC in git repo and syncing via ArgoCD the following sync error happens:

```
one or more objects failed to apply, reason: error when patching "/dev/shm/2228869740": StatefulSet.apps "sx-mimir-ingester-zone-a" is invalid: spec: Forbidden: updates to statefulset spec for fields other than 'replicas', 'ordinals', 'template', 'updateStrategy', 'persistentVolumeClaimRetentionPolicy' and 'minReadySeconds' are forbidden,error when patching "/dev/shm/2372432679": StatefulSet.apps "sx-mimir-ingester-zone-b" is invalid: spec: Forbidden: updates to statefulset spec for fields other than 'replicas', 'ordinals', 'template', 'updateStrategy', 'persistentVolumeClaimRetentionPolicy' and 'minReadySeconds' are forbidden,error when patching "/dev/shm/657813136": StatefulSet.apps "sx-mimir-ingester-zone-c" is invalid: spec: Forbidden: updates to statefulset spec for fields other than 'replicas', 'ordinals', 'template', 'updateStrategy', 'persistentVolumeClaimRetentionPolicy' and 'minReadySeconds' are forbidden. Retrying attempt #2 at 6:43AM.
```

How it worked in our environment with the example sts `sx-mimir-ingester-zone-c` (works the same for every other ingester of course).

1. disable auto-sync in bootstrap app and mimir app
2. resize pvc with `kubectl patch pvc -n mimir storage-sx-mimir-ingester-zone-c-0 -p '{"spec": {"resources": {"requests": {"storage": "'20Gi'"}}}}'`
3. after some time this pvc should have the new size. check with `kubectl get pvc -n mimir storage-sx-mimir-ingester-zone-c-0` . Check with `kubectl get events -n mimir` for the resizing events.
4. also the underlying pv should have the new size. check with: `kubectl get pv |grep storage-sx-mimir-ingester-zone-c-0`
5. orphan delete sts `sx-mimir-ingester-zone-c`
![image](https://github.com/user-attachments/assets/1fb576ca-3c1e-4a9f-a38a-b2c26baec9f2)

6. sync ingester sts `sx-mimir-ingester-zone-c`
![image](https://github.com/user-attachments/assets/1d0c39b1-b13a-4b9d-aabf-6636fd134105)

7. enable auto-sync in bootstrap app and mimir app again

Matches with this (even though it is for Tempo) except that it doesn't explain the ArgoCD part: https://grafana.com/docs/tempo/latest/operations/ingester_pvcs/

TBD: we definitly need to monitor the ingester PVCs!


## write to long-term storage failed - Storage backend has reached its minimum free drive threshold

mimir ingester pods log error concerning full s3 long-term storage. This could happen in parallel with the "full WAL storage" warning.

```
kubectl logs sx-mimir-ingester-zone-c-0 -n mimir

ts=2024-09-10T07:34:52.173342654Z caller=shipper.go:162 level=error user=anonymous msg="uploading new block to long-term storage failed" block=01J71SHADT7DGVPR2JKCY5H8EE err="upload chunks: upload file /data/tsdb/anonymous/01J71SHADT7DGVPR2JKCY5H8EE/chunks/000001 as 01J71SHADT7DGVPR2JKCY5H8EE/chunks/000001: upload s3 object: Storage backend has reached its minimum free drive threshold. Please delete a few objects to proceed."!
```

When using minio default s3 long-term storage this could be increased by configuring the size in the values file like this

```
  minio:
    persistence:
      size: 20Gi
```

example commit: https://github.com/suxess-it/sx-cnp-oss/pull/538/commits/2afbce2151aa8e9e3e535702d60fd3650efffcb9

During ArgoCD sync you probably will see the following event:

![image](https://github.com/user-attachments/assets/033347bd-315f-43b8-a799-a784718e932d)

or via kubectl:

```
kubectl get events -n mimir

116s        Warning   ExternalExpanding            persistentvolumeclaim/sx-mimir-minio   waiting for an external controller to expand this PVC
116s        Normal    Resizing                     persistentvolumeclaim/sx-mimir-minio   External resizer is resizing volume pvc-386dcd78-923b-435b-a902-44da42783d8e
116s        Normal    FileSystemResizeRequired     persistentvolumeclaim/sx-mimir-minio   Require file system resize of volume on node
84s         Normal    FileSystemResizeSuccessful   persistentvolumeclaim/sx-mimir-minio   MountVolume.NodeExpandVolume succeeded for volume "pvc-386dcd78-923b-435b-a902-44da42783d8e" shoot--suxessit--lab-default-76d97-6c6hr
```

Check the new filesystem size of the PVC:

```
kubectl get pvc -n mimir sx-mimir-minio

NAME             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
sx-mimir-minio   Bound    pvc-386dcd78-923b-435b-a902-44da42783d8e   20Gi       RWO            premium        26d
```

Check the filesystem usage inside minio pod:

```
kubectl exec sx-mimir-minio-74b979965-fl4fz -n mimir -it -- df -h /export
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme1n8     99G   27G   72G  28% /export
```


## Grafana - No data because scrapeInterval is 60 seconds

Set Min Step of 2 minutes if you use `$__rate_interval` and k8s-monitoring chart has default scrapeInterval of 60 seconds

see https://grafana.com/blog/2020/09/28/new-in-grafana-7.2-__rate_interval-for-prometheus-rate-queries-that-just-work/


