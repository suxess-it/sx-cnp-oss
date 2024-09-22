


# Storage backend has reached its minimum free drive threshold

You see errors in the loki logs like this:

```
kubectl logs sx-loki-0 -n loki

level=error ts=2024-09-09T22:00:24.389793753Z caller=flush.go:178 component=ingester loop=13 org_id=fake msg="failed to flush" retries=1 err="failed to flush chunks: store put chunk: XMinioStorageFull: Storage backend has reached its minimum free drive threshold. Please delete a few objects to proceed.\n\tstatus code: 507, request id: 17F3B263E8B79115, host id: , num_chunks: 40, labels: {cluster=\"secobs1\", instance=\"loki.source.kubernetes_events.cluster_events\", job=\"integrations/kubernetes/eventhandler\", namespace=\"external-secrets\", service_name=\"integrations/kubernetes/eventhandler\"}"
```

Solution: incease loki minio s3 storage


increase size in values:

```
  minio:
    enabled: true
    persistence:
      size: 100Gi
```

However, when syncing with ArgoCD you get the following error:

```
Failed to compare desired state to live state: failed to calculate diff: error calculating server side diff: serverSideDiff error: error running server side apply in dryrun mode for resource StatefulSet/sx-loki-minio: StatefulSet.apps "sx-loki-minio" is invalid: spec: Forbidden: updates to statefulset spec for fields other than 'replicas', 'ordinals', 'template', 'updateStrategy', 'persistentVolumeClaimRetentionPolicy' and 'minReadySeconds' are forbidden
```

This problem is the same as with the ingester WAL pvcs in mimir. So after changing the values in git you need to do the following:

1. disable auto-sync in bootstrap app and loki app
2. resize pvc with 
```
kubectl patch pvc -n loki export-0-sx-loki-minio-0 -p '{"spec": {"resources": {"requests": {"storage": "'100Gi'"}}}}'
kubectl patch pvc -n loki export-1-sx-loki-minio-0 -p '{"spec": {"resources": {"requests": {"storage": "'100Gi'"}}}}'
```
3. after some time this pvc should have the new size. check with `kubectl get pvc -n loki` . Check with `kubectl get events -n loki` for the resizing events.
4. orphan delete sts `sx-loki-minio` in argocd:
   ![image](https://github.com/user-attachments/assets/4f451912-619f-49d2-9b27-d92d1f09f38a)

6. sync `sx-loki-minio`
7. enable auto-sync in bootstrap app and loki app again

