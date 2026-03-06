# Ingress Setup for Inference Endpoint

This repo now includes shared ingress at `.kube/base/ingress.yaml`.

Before applying it, install an ingress controller. Your cluster currently has no `IngressClass`.

## 1) Install ingress-nginx

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=300s
kubectl get ingressclass
```

Expected: `nginx` ingress class appears.

## 2) Configure host and TLS secret name

Edit `.kube/base/ingress.yaml`:

- replace `llm.example.com` with your real domain
- keep/update TLS secret name `llm-tls`

## 3) DNS mapping

Get ingress controller external address:

```bash
kubectl -n ingress-nginx get svc ingress-nginx-controller
```

Point your DNS A record (or CNAME) for the domain in ingress to that address.

## 4) TLS options

### Option A: Existing TLS cert secret

If you already have cert files:

```bash
kubectl -n inference-engine create secret tls llm-tls \
  --cert=fullchain.pem \
  --key=privkey.pem
```

### Option B: cert-manager (recommended)

Install cert-manager first, then create an issuer and annotate ingress.

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl -n cert-manager rollout status deploy/cert-manager --timeout=300s
```

## 5) Deploy and verify

```bash
kubectl apply -k .kube/middleware
kubectl apply -k .kube/vllm
kubectl -n inference-engine get ingress
kubectl -n inference-engine describe ingress llm-ingress
```

Test externally:

```bash
curl https://<your-domain>/v1/models \
  -H "Authorization: Bearer <middleware-api-key>"

curl https://<your-domain>/v1/chat/completions \
  -H "Authorization: Bearer <middleware-api-key>" \
  -H "Content-Type: application/json" \
  -d '{"model":"Qwen/Qwen2.5-3B-Instruct","messages":[{"role":"user","content":"hello"}]}'
```

## Notes

- Keep using `inference-engine` namespace.
- If endpoint returns 502, check `ingress-nginx-controller` logs, `middleware-service` endpoints, and `llm-service` endpoints.
- If using only HTTP temporarily, remove `spec.tls` section from ingress.
