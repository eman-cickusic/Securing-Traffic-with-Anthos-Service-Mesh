# Key Concepts & Diagrams

## Authentication in Anthos Service Mesh

Anthos Service Mesh provides two types of authentication:

1. **Peer Authentication (Service-to-Service)**
   - Controls whether communication between services is encrypted and authenticated
   - Configurable via `PeerAuthentication` resources

2. **Request Authentication (End-User)**
   - Validates JWT tokens in requests
   - Configurable via `RequestAuthentication` resources

## mTLS Modes

![mTLS Modes Diagram](https://raw.githubusercontent.com/istio/istio.io/master/content/en/docs/concepts/security/authn.svg)

### PERMISSIVE Mode (Default)
- Services accept both plaintext and mTLS traffic
- Allows incremental adoption of mTLS
- mTLS is used when both client and server support it

### STRICT Mode
- Services only accept authenticated mTLS traffic
- All plaintext traffic is rejected
- Requires all clients to support mTLS

## Architecture Diagram

```
┌─────────────────┐      ┌─────────────────┐
│  mtls-client    │      │  mtls-service   │
│                 │      │                 │
│  ┌───────────┐  │      │  ┌───────────┐  │
│  │   sleep   │──┼──────┼─▶│  httpbin  │  │
│  └───────────┘  │      │  └───────────┘  │
│                 │      │                 │
│  Istio Enabled  │      │  Istio Enabled  │
└─────────────────┘      └─────────────────┘
         │                       ▲
         │                       │
         │                       │
         ▼                       │
┌─────────────────┐      ┌─────────────────┐
│  legacy-client  │      │ legacy-service  │
│                 │      │                 │
│  ┌───────────┐  │      │  ┌───────────┐  │
│  │   sleep   │──┼──────┼─▶│  httpbin  │  │
│  └───────────┘  │      │  └───────────┘  │
│                 │      │                 │
│    No Istio     │      │    No Istio     │
└─────────────────┘      └─────────────────┘
```

## Traffic Flow with PERMISSIVE Mode (Default)

| Source       | Destination   | Traffic Type | Status |
|--------------|---------------|--------------|--------|
| mtls-client  | mtls-service  | mTLS         | ✅     |
| mtls-client  | legacy-service| Plaintext    | ✅     |
| legacy-client| mtls-service  | Plaintext    | ✅     |
| legacy-client| legacy-service| Plaintext    | ✅     |

## Traffic Flow with STRICT Mode mTLS

| Source       | Destination   | Traffic Type | Status |
|--------------|---------------|--------------|--------|
| mtls-client  | mtls-service  | mTLS         | ✅     |
| mtls-client  | legacy-service| Plaintext    | ✅     |
| legacy-client| mtls-service  | Plaintext    | ❌     |
| legacy-client| legacy-service| Plaintext    | ✅     |

## Authorization Concepts

Authorization in Anthos Service Mesh determines which requests are permitted using `AuthorizationPolicy` resources. Policy decisions are based on:

1. **Identity** - Who is making the request?
   - Service account
   - JWT principal

2. **Source** - Where is the request coming from?
   - Namespace
   - IP address

3. **Operation** - What is being requested?
   - HTTP method (GET, POST, etc.)
   - URI path
   - API version

### Authorization Policy Example

```yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: httpbin-policy
spec:
  selector:
    matchLabels:
      app: httpbin
  action: ALLOW
  rules:
  - from:
    - source:
        namespaces: ["mtls-client"]
    to:
    - operation:
        methods: ["GET"]
        paths: ["/ip", "/headers"]
    when:
    - key: request.auth.claims[iss]
      values: ["testing@secure.istio.io"]
```

## Security Best Practices

1. **Enable STRICT mode mTLS** for production environments
2. **Use namespace-level policies** for better isolation
3. **Implement JWT authentication** for end-user validation
4. **Define granular authorization policies** based on methods and paths
5. **Monitor traffic patterns** in the Anthos Service Mesh dashboard
