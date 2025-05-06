#!/bin/bash
# Test script for Anthos Service Mesh security features

# Text formatting
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}===========================================================${NC}"
echo -e "${BLUE}     Testing Anthos Service Mesh Security Features         ${NC}"
echo -e "${BLUE}===========================================================${NC}"

# Get the JWT token for testing
echo -e "\n${YELLOW}Downloading JWT token for testing...${NC}"
TOKEN=$(curl https://raw.githubusercontent.com/istio/istio/release-1.8/security/tools/jwt/samples/demo.jwt -s)
echo -e "JWT token payload:"
echo "$TOKEN" | cut -d '.' -f2 - | base64 --decode -

# Function to test communication patterns
test_communication_patterns() {
  echo -e "\n${YELLOW}Testing communication between services...${NC}"
  
  for from in "mtls-client" "legacy-client"; do
    for to in "mtls-service" "legacy-service"; do
      response=$(kubectl exec $(kubectl get pod -l app=sleep -n ${from} -o jsonpath={.items..metadata.name}) -c sleep -n ${from} -- \
        curl "http://httpbin.${to}:8000/ip" -s -o /dev/null -w "%{http_code}")
      
      if [ "$response" == "200" ]; then
        echo -e "${GREEN}✓ sleep.${from} to httpbin.${to}: ${response}${NC}"
      else
        echo -e "${RED}✗ sleep.${from} to httpbin.${to}: ${response}${NC}"
      fi
    done
  done
}

# Test default PERMISSIVE mode behavior
echo -e "\n${YELLOW}1. Testing default PERMISSIVE mode behavior${NC}"
echo "In this mode, all services should be able to communicate with each other."
test_communication_patterns

# Apply mesh-wide STRICT mTLS
echo -e "\n${YELLOW}2. Applying mesh-wide STRICT mTLS policy${NC}"
kubectl apply -f - <<EOF
apiVersion: "security.istio.io/v1beta1"
kind: "PeerAuthentication"
metadata:
  name: "mesh-wide-mtls"
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
EOF

echo -e "Waiting for policy to propagate..."
sleep 5

echo -e "\n${YELLOW}Testing after applying mesh-wide STRICT mTLS${NC}"
echo "In this mode, legacy clients should not be able to communicate with mesh services."
test_communication_patterns

# Clean up mesh-wide mTLS policy
echo -e "\n${YELLOW}Removing mesh-wide STRICT mTLS policy${NC}"
kubectl delete peerauthentication mesh-wide-mtls -n istio-system
echo "Waiting for policy removal to propagate..."
sleep 5

# Test namespace-specific STRICT mTLS
echo -e "\n${YELLOW}3. Testing namespace-specific STRICT mTLS policy${NC}"

# Make sure the strict-mtls-service namespace exists
kubectl get ns strict-mtls-service &>/dev/null || kubectl create ns strict-mtls-service

# Make sure Istio sidecar injection is enabled
DEPLOYMENT=$(kubectl get deployments -n istio-system | grep istiod)
VERSION=asm-$(echo $DEPLOYMENT | cut -d'-' -f 3)-$(echo $DEPLOYMENT | cut -d'-' -f 4 | cut -d' ' -f 1)
kubectl label namespace strict-mtls-service istio.io/rev=${VERSION} --overwrite

# Deploy httpbin service
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.6/samples/httpbin/httpbin.yaml -n strict-mtls-service

echo "Waiting for service to be available..."
kubectl wait --for=condition=available --timeout=60s deployment/httpbin -n strict-mtls-service

# Apply namespace-specific STRICT mTLS policy
kubectl apply -f - <<EOF
apiVersion: "security.istio.io/v1beta1"
kind: "PeerAuthentication"
metadata:
  name: "restricted-mtls"
  namespace: strict-mtls-service
spec:
  mtls:
    mode: STRICT
EOF

echo "Waiting for policy to propagate..."
sleep 5

echo -e "\n${YELLOW}Testing namespace-specific STRICT mTLS${NC}"

# Test access from legacy client (should fail)
response=$(kubectl exec $(kubectl get pod -l app=sleep -n legacy-client -o jsonpath={.items..metadata.name}) -c sleep -n legacy-client -- \
  curl "http://httpbin.strict-mtls-service:8000/ip" -s -o /dev/null -w "%{http_code}" || echo "000")

if [ "$response" == "000" ]; then
  echo -e "${GREEN}✓ legacy-client to strict-mtls-service blocked as expected: ${response}${NC}"
else
  echo -e "${RED}✗ legacy-client to strict-mtls-service should be blocked, got: ${response}${NC}"
fi

# Test access from mesh client (should succeed)
response=$(kubectl exec $(kubectl get pod -l app=sleep -n mtls-client -o jsonpath={.items..metadata.name}) -c sleep -n mtls-client -- \
  curl "http://httpbin.strict-mtls-service:8000/ip" -s -o /dev/null -w "%{http_code}")

if [ "$response" == "200" ]; then
  echo -e "${GREEN}✓ mtls-client to strict-mtls-service allowed as expected: ${response}${NC}"
else
  echo -e "${RED}✗ mtls-client to strict-mtls-service should be allowed, got: ${response}${NC}"
fi

# Clean up namespace-specific mTLS policy
kubectl delete peerauthentication restricted-mtls -n strict-mtls-service

# Test JWT Authentication
echo -e "\n${YELLOW}4. Testing JWT Authentication${NC}"

# Apply RequestAuthentication
kubectl apply -f - <<EOF
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
EOF

echo "Waiting for JWT authentication policy to propagate..."
sleep 5

# Test with invalid JWT
echo -e "\n${YELLOW}Testing with invalid JWT token${NC}"
response=$(kubectl exec "$(kubectl get pod -l app=sleep -n mtls-client -o jsonpath={.items..metadata.name})" -c sleep -n mtls-client -- \
  curl "http://httpbin.mtls-service:8000/headers" -s -o /dev/null -H "Authorization: Bearer invalidToken" -w "%{http_code}")

if [ "$response" == "401" ]; then
  echo -e "${GREEN}✓ Request with invalid JWT correctly rejected: ${response}${NC}"
else
  echo -e "${RED}✗ Request with invalid JWT should be rejected, got: ${response}${NC}"
fi

# Test without JWT
echo -e "\n${YELLOW}Testing without JWT token${NC}"
response=$(kubectl exec "$(kubectl get pod -l app=sleep -n mtls-client -o jsonpath={.items..metadata.name})" -c sleep -n mtls-client -- \
  curl "http://httpbin.mtls-service:8000/headers" -s -o /dev/null -w "%{http_code}")

if [ "$response" == "200" ]; then
  echo -e "${GREEN}✓ Request without JWT allowed as expected: ${response}${NC}"
else
  echo -e "${RED}✗ Request without JWT should be allowed, got: ${response}${NC}"
fi

# Test Authorization Policy
echo -e "\n${YELLOW}5. Testing Authorization Policy${NC}"

# Apply AuthorizationPolicy requiring JWT
kubectl apply -f - <<EOF
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
EOF

echo "Waiting for authorization policy to propagate..."
sleep 5

# Test with valid JWT
echo -e "\n${YELLOW}Testing with valid JWT token${NC}"
response=$(kubectl exec "$(kubectl get pod -l app=sleep -n mtls-client -o jsonpath={.items..metadata.name})" -c sleep -n mtls-client -- \
  curl "http://httpbin.mtls-service:8000/headers" -s -o /dev/null -H "Authorization: Bearer $TOKEN" -w "%{http_code}")

if [ "$response" == "200" ]; then
  echo -e "${GREEN}✓ Request with valid JWT allowed as expected: ${response}${NC}"
else
  echo -e "${RED}✗ Request with valid JWT should be allowed, got: ${response}${NC}"
fi

# Test without JWT
echo -e "\n${YELLOW}Testing without JWT token (should be denied now)${NC}"
response=$(kubectl exec "$(kubectl get pod -l app=sleep -n mtls-client -o jsonpath={.items..metadata.name})" -c sleep -n mtls-client -- \
  curl "http://httpbin.mtls-service:8000/headers" -s -o /dev/null -w "%{http_code}")

if [ "$response" == "403" ]; then
  echo -e "${GREEN}✓ Request without JWT correctly denied: ${response}${NC}"
else
  echo -e "${RED}✗ Request without JWT should be denied, got: ${response}${NC}"
fi

# Update AuthorizationPolicy to restrict HTTP methods and paths
echo -e "\n${YELLOW}6. Testing Authorization Policy with method and path restrictions${NC}"

kubectl apply -f - <<EOF
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
    to:
    - operation:
        methods: ["GET"]
        paths: ["/ip"]
EOF

echo "Waiting for updated authorization policy to propagate..."
sleep 5

# Test GET to /ip with valid JWT (should work)
echo -e "\n${YELLOW}Testing GET to /ip with valid JWT token${NC}"
response=$(kubectl exec "$(kubectl get pod -l app=sleep -n mtls-client -o jsonpath={.items..metadata.name})" -c sleep -n mtls-client -- \
  curl "http://httpbin.mtls-service:8000/ip" -s -o /dev/null -H "Authorization: Bearer $TOKEN" -w "%{http_code}")

if [ "$response" == "200" ]; then
  echo -e "${GREEN}✓ GET to /ip with valid JWT allowed as expected: ${response}${NC}"
else
  echo -e "${RED}✗ GET to /ip with valid JWT should be allowed, got: ${response}${NC}"
fi

# Test GET to /headers with valid JWT (should fail)
echo -e "\n${YELLOW}Testing GET to /headers with valid JWT token${NC}"
response=$(kubectl exec "$(kubectl get pod -l app=sleep -n mtls-client -o jsonpath={.items..metadata.name})" -c sleep -n mtls-client -- \
  curl "http://httpbin.mtls-service:8000/headers" -s -o /dev/null -H "Authorization: Bearer $TOKEN" -w "%{http_code}")

if [ "$response" == "403" ]; then
  echo -e "${GREEN}✓ GET to /headers with valid JWT correctly denied: ${response}${NC}"
else
  echo -e "${RED}✗ GET to /headers with valid JWT should be denied, got: ${response}${NC}"
fi

# Clean up
echo -e "\n${YELLOW}7. Cleaning up policies${NC}"
kubectl delete requestauthentication jwt-example -n mtls-service
kubectl delete authorizationpolicy require-jwt -n mtls-service

echo -e "\n${BLUE}===========================================================${NC}"
echo -e "${BLUE}                  Testing Complete                         ${NC}"
echo -e "${BLUE}===========================================================${NC}"
