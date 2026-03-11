apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${dynamo_model_cache_pvc}
  namespace: ${namespace}
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 300Gi
  storageClassName: gp3
