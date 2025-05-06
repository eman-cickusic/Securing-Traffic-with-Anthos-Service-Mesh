# Security Policies

## mesh-mtls-policy.yaml

```yaml
# PeerAuthentication policy to enforce STRICT mTLS mode across the entire mesh
apiVersion: "security.istio.io/v1beta1"
kind: "PeerAuthentication"
metadata:
  name: "mesh-wide-mtls"
spec:
  mtls:
    mode: STRICT
```

## namespace-mtls-policy.yaml

```yaml
# PeerAuthentication policy to enforce STRICT mTLS mode on a specific namespace
apiVersion: "security.istio.io/v1beta1"
kind: "PeerAuthentication"
metadata:
  name: "restricted-mtls"
  namespace: strict-mtls-service
spec:
  mtls:
    mode: STRICT
```

## jwt-auth.yaml

```yaml
# RequestAuthentication resource to define JWT validation for the httpbin service
apiVersion: "security.istio.io/v1beta1"
kind: "RequestAuthentication"
metadata:
  name: "jwt-example"
  namespace: mtls-service
spec:
  selector:
    matchLabels:
      app: httpbin
  jwtRules:
  - issuer: "testing@secure.istio.io"
    jwksUri: "https://raw.githubusercontent.com/istio/istio/release-1.8/security/tools/jwt/samples/jwks.json"
```

## authorization-policies.yaml

### Basic JWT Authorization Policy

```yaml
# AuthorizationPolicy to require JWT authentication for all requests
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: require-jwt
  namespace: mtls-service
spec:
  selector:
    matchLabels:
      app: httpbin
  action: ALLOW
  rules:
  - from:
    - source:
        requestPrincipals: ["testing@secure.istio.io/testing@secure.istio.io"]
```

### Advanced Authorization Policy with HTTP Method and Path

```yaml
# AuthorizationPolicy to require JWT authentication and limit to specific HTTP methods and paths
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: require-jwt-with-method-path
  namespace: mtls-service
spec:
  selector:
    matchLabels:
      app: httpbin
  action: ALLOW
  rules:
  - from:
    - source:
        requestPrincipals: ["testing@secure.istio.io/testing@secure.istio.io"]
    to:
    - operation:
        methods: ["GET"]
        paths: ["/ip"]
```
