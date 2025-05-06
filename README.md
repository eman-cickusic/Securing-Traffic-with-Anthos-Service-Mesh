# Securing Traffic with Anthos Service Mesh

This repository demonstrates how to implement and configure security features in Anthos Service Mesh, including mTLS authentication, JWT authorization, and HTTP traffic policies.

## Overview

Anthos Service Mesh security helps mitigate insider threats and reduce the risk of data breaches by ensuring that all communications between workloads are encrypted, mutually authenticated, and authorized.

This project demonstrates:
- PERMISSIVE mode mTLS allowing both plaintext and mTLS traffic
- STRICT mode mTLS across the entire service mesh
- Namespace-scoped STRICT mode mTLS
- Request authentication using JWTs
- Authorization policies for HTTP traffic

## Prerequisites

- Google Cloud account with a GKE cluster
- Anthos Service Mesh installed
- `kubectl` configured to access your cluster

## Project Structure

```
.
├── README.md
├── deployment/
│   ├── httpbin.yaml
│   └── sleep.yaml
├── security/
│   ├── mesh-mtls-policy.yaml
│   ├── namespace-mtls-policy.yaml
│   ├── jwt-auth.yaml
│   └── authorization-policies.yaml
└── scripts/
    └── test-requests.sh
```

## Lab Environment Setup

The lab uses a GKE cluster with Anthos Service Mesh installed. Four namespaces are created to demonstrate different security configurations:

- `mtls-client`: Client namespace with Istio sidecar injection
- `mtls-service`: Service namespace with Istio sidecar injection
- `legacy-client`: Client namespace without Istio sidecar injection
- `legacy-service`: Service namespace without Istio sidecar injection
- `strict-mtls-service`: Service namespace with strict mTLS enforcement

## Step-by-Step Guide

### 1. Create Namespaces

```bash
kubectl create ns mtls-client
kubectl create ns mtls-service
kubectl create ns legacy-client
kubectl create ns legacy-service
kubectl create ns strict-mtls-service
```

### 2. Enable Istio Sidecar Injection

```bash
# Get the revision label for the installed Istio version
export DEPLOYMENT=$(kubectl get deployments -n istio-system | grep istiod)
export VERSION=asm-$(echo $DEPLOYMENT | cut -d'-' -f 3)-$(echo $DEPLOYMENT | cut -d'-' -f 4 | cut -d' ' -f 1)

# Enable auto-injection on the namespaces
kubectl label namespace mtls-client istio.io/rev=${VERSION} --overwrite
kubectl label namespace mtls-service istio.io/rev=${VERSION} --overwrite
kubectl label namespace strict-mtls-service istio.io/rev=${VERSION} --overwrite
```

### 3. Deploy Services

Deploy the sleep client and httpbin server in each namespace:

```bash
# Deploy to legacy namespaces
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.6/samples/sleep/sleep.yaml -n legacy-client
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.6/samples/httpbin/httpbin.yaml -n legacy-service

# Deploy to mesh-enabled namespaces
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.6/samples/sleep/sleep.yaml -n mtls-client
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.6/samples/httpbin/httpbin.yaml -n mtls-service
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.6/samples/httpbin/httpbin.yaml -n strict-mtls-service
```

### 4. Test Default Behavior (PERMISSIVE Mode)

By default, Istio configures destination workloads in PERMISSIVE mode, allowing both plaintext and mTLS traffic:

```bash
# Test all communication paths
for from in "mtls-client" "legacy-client"; do
  for to in "mtls-service" "legacy-service"; do
    kubectl exec $(kubectl get pod -l app=sleep -n ${from} -o jsonpath={.items..metadata.name}) -c sleep -n ${from} -- curl "http://httpbin.${to}:8000/ip" -s -o /dev/null -w "sleep.${from} to httpbin.${to}: %{http_code}\n"
  done
done
```

### 5. Enable STRICT mTLS Across the Mesh

Apply a PeerAuthentication policy to enforce STRICT mTLS mode across the entire mesh:

```bash
kubectl apply -n istio-system -f security/mesh-mtls-policy.yaml
```

### 6. Enable STRICT mTLS for a Specific Namespace

Apply a namespace-scoped PeerAuthentication policy:

```bash
kubectl apply -f security/namespace-mtls-policy.yaml
```

### 7. Configure JWT Authentication

Set up RequestAuthentication to validate JWTs:

```bash
kubectl apply -f security/jwt-auth.yaml
```

### 8. Configure Authorization Policies

Apply AuthorizationPolicy to enforce access based on JWT and HTTP method/path:

```bash
kubectl apply -f security/authorization-policies.yaml
```

## Testing

Run the provided script to test different authentication and authorization scenarios:

```bash
./scripts/test-requests.sh
```

## Key Insights

1. **mTLS Modes:**
   - PERMISSIVE mode: Services accept both plaintext and mTLS traffic (default)
   - STRICT mode: Services only accept authenticated mTLS traffic

2. **Authentication Levels:**
   - Peer Authentication (service-to-service)
   - Request Authentication (end-user authentication via JWT)

3. **Authorization:**
   - Control access based on identity, source, method, path, etc.
   - Apply at mesh-level, namespace-level, or workload-level

## References

- [Anthos Service Mesh Documentation](https://cloud.google.com/service-mesh/docs)
- [Istio Authentication Docs](https://istio.io/latest/docs/concepts/security/#authentication)
- [Istio Authorization Docs](https://istio.io/latest/docs/concepts/security/#authorization)
