# Network Policy Security Exercise

## Learning Objectives

By completing this exercise, you will learn:

- How to implement **zero-trust networking** principles in Kubernetes
- How to use **NetworkPolicies** to prevent lateral movement attacks
- How to enforce **network segmentation** between application tiers
- How to control **egress traffic** to prevent data exfiltration
- How to implement **namespace isolation** for multi-tenant environments
- How to test and verify network security controls

## Exercise Pattern

This exercise follows a hands-on, attack-then-defend approach:

1. **Deploy insecure configuration** - Set up a 3-tier application without network policies
2. **Test exploits** - Demonstrate lateral movement and data exfiltration attacks
3. **Understand the threat model** - Learn what attackers can do
4. **Apply security controls** - Implement NetworkPolicies to block attacks
5. **Verify defenses** - Confirm attacks are now prevented

## Architecture Overview

We'll deploy a typical 3-tier web application:

```
┌─────────────┐
│  Frontend   │  (nginx)
│  Port: 80   │
└──────┬──────┘
       │
       │ Should only talk to Backend
       │
       ▼
┌─────────────┐
│   Backend   │  (API server)
│  Port: 8080 │
└──────┬──────┘
       │
       │ Should only talk to Database
       │
       ▼
┌─────────────┐
│  Database   │  (PostgreSQL)
│  Port: 5432 │
└─────────────┘
```

**Without NetworkPolicies:**
- ❌ Frontend can directly access Database (bypass backend!)
- ❌ Any pod can access external internet (data exfiltration!)
- ❌ Pods can access other namespaces (namespace escape!)

**With NetworkPolicies:**
- ✅ Frontend → Backend only
- ✅ Backend → Database only
- ✅ Controlled egress (DNS only where needed)
- ✅ Namespace isolation

## Prerequisites

- A Kubernetes cluster with a CNI that supports NetworkPolicies:
  - **Calico** (recommended)
  - **Cilium**
  - **Weave Net**
  - **Azure CNI** (AKS)
  - **Google Network Policy** (GKE)
  
- **NOT supported:** Flannel (basic mode), kubenet

To check if NetworkPolicies are supported:
```bash
kubectl api-resources | grep networkpolicies
```

## Step 1: Deploy Insecure Configuration

First, let's deploy our 3-tier application **without** any NetworkPolicies.

```bash
# Deploy all components
kubectl apply -f start/

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=webapp --timeout=120s

# Check deployment status
kubectl get pods -l app=webapp
```

<details>
<summary>📋 Expected Output</summary>

```
namespace/default unchanged
deployment.apps/database created
service/database created
deployment.apps/backend created
service/backend created
deployment.apps/frontend created
service/frontend created

NAME                        READY   STATUS    RESTARTS   AGE
backend-xxxxxxxxx-xxxxx     1/1     Running   0          30s
database-xxxxxxxxx-xxxxx    1/1     Running   0          30s
frontend-xxxxxxxxx-xxxxx    1/1     Running   0          30s
```

</details>

## Step 2: Test Connectivity (No Network Policies)

Now let's test the connectivity **before** applying NetworkPolicies to see the security issues.

### Test 1: Frontend → Backend (Legitimate Traffic ✅)

This is normal application traffic and should work:

```bash
kubectl exec -it deployment/frontend -- curl -s http://backend:8080
```

<details>
<summary>📋 Expected Output</summary>

```
{"status":"healthy","service":"backend-api"}
```

✅ **PASS** - Frontend can reach backend as expected.

</details>

### Test 2: Backend → Database (Legitimate Traffic ✅)

The backend needs to access the database - this is legitimate:

```bash
kubectl exec -it deployment/backend -- nc -zv database 5432
```

<details>
<summary>📋 Expected Output</summary>

```
database (10.x.x.x:5432) open
```

✅ **PASS** - Backend can reach database as expected.

</details>

### Test 3: Frontend → Database (ATTACK! ❌)

**This is a security issue!** The frontend should NOT be able to bypass the backend and access the database directly. This enables:
- SQL injection attacks from compromised frontend
- Data exfiltration
- Lateral movement

```bash
kubectl exec -it deployment/frontend -- nc -zv database 5432
```

<details>
<summary>📋 Expected Output (Before Network Policies)</summary>

```
database (10.x.x.x:5432) open
```

❌ **SECURITY ISSUE** - Frontend can directly access database, bypassing backend logic!

</details>

### Test 4: Egress to Internet (Data Exfiltration Risk ❌)

Without egress controls, compromised pods can exfiltrate data:

```bash
kubectl exec -it deployment/frontend -- curl -s -I https://google.com --connect-timeout 5
```

<details>
<summary>📋 Expected Output (Before Network Policies)</summary>

```
HTTP/2 200
content-type: text/html; charset=ISO-8859-1
...
```

❌ **SECURITY ISSUE** - Pods can reach external internet without restriction!

</details>

### Test 5: Cross-Namespace Access (Namespace Escape ❌)

Create a production namespace to test cross-namespace access:

```bash
# Create production namespace with a service
kubectl create namespace production
kubectl run prod-app --image=nginx:alpine -n production --port=80
kubectl expose pod prod-app --port=80 -n production

# Try to access production from default namespace
kubectl exec -it deployment/frontend -- curl -s http://prod-app.production.svc.cluster.local --connect-timeout 5
```

<details>
<summary>📋 Expected Output (Before Network Policies)</summary>

```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
```

❌ **SECURITY ISSUE** - Pods can access services in other namespaces without restriction!

</details>

## Step 3: Understand the Threat Model

### Attack Vectors Demonstrated

1. **Lateral Movement**
   - Compromised frontend pod → Direct database access
   - Bypass backend validation and business logic
   - SQL injection, data theft

2. **Data Exfiltration**
   - Any pod can reach external internet
   - Attacker can send stolen credentials/data out
   - No egress controls

3. **Privilege Escalation**
   - Cross-namespace communication allowed
   - Can probe/attack production workloads
   - Namespace boundaries don't provide security

### Why This Matters

In a real attack scenario:
1. Attacker compromises frontend pod (via XSS, RCE, etc.)
2. Without NetworkPolicies, attacker can:
   - Access database directly → Steal all data
   - Reach internet → Exfiltrate data to attacker-controlled server
   - Scan other namespaces → Pivot to more sensitive workloads
3. Blast radius is **entire cluster**, not just one pod

## Step 4: Apply NetworkPolicies (Your Turn!)

Before looking at the solution, try implementing NetworkPolicies yourself!

<details>
<summary>💡 Hint 1: Start with Default Deny</summary>

The foundation of zero-trust networking is **default deny all**:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: default
spec:
  podSelector: {}  # Empty selector = all pods
  policyTypes:
  - Ingress
```

This blocks ALL ingress traffic by default. Then you explicitly allow what's needed.

</details>

<details>
<summary>💡 Hint 2: Allow Frontend → Backend</summary>

Use `podSelector` with labels to allow traffic between specific tiers:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
spec:
  podSelector:
    matchLabels:
      tier: backend  # Apply to backend pods
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: frontend  # Allow from frontend pods
    ports:
    - protocol: TCP
      port: 8080
```

</details>

<details>
<summary>💡 Hint 3: Control Egress</summary>

Don't forget egress policies! They prevent data exfiltration:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-egress-policy
spec:
  podSelector:
    matchLabels:
      tier: frontend
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          tier: backend
  # Also allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

</details>

## Step 5: Deploy NetworkPolicies

When ready, apply the pre-configured NetworkPolicies:

```bash
# Apply all network policies
kubectl apply -f done/

# Verify policies are created
kubectl get networkpolicies
```

<details>
<summary>📋 Expected Output</summary>

```
networkpolicy.networking.k8s.io/default-deny-ingress created
networkpolicy.networking.k8s.io/allow-frontend-to-backend created
networkpolicy.networking.k8s.io/allow-backend-to-database created
networkpolicy.networking.k8s.io/frontend-egress-policy created
networkpolicy.networking.k8s.io/backend-egress-policy created
networkpolicy.networking.k8s.io/database-egress-policy created
networkpolicy.networking.k8s.io/deny-from-other-namespaces created

NAME                          POD-SELECTOR      AGE
allow-backend-to-database     tier=database     5s
allow-frontend-to-backend     tier=backend      5s
backend-egress-policy         tier=backend      5s
database-egress-policy        tier=database     5s
default-deny-ingress          <none>            5s
frontend-egress-policy        tier=frontend     5s
deny-from-other-namespaces    <none>            5s
```

</details>

### What Did We Apply?

1. **01-default-deny.yml** - Deny all ingress by default (zero-trust foundation)
2. **02-allow-frontend-to-backend.yml** - Explicitly allow Frontend → Backend:8080
3. **03-allow-backend-to-database.yml** - Explicitly allow Backend → Database:5432
4. **04-deny-external-egress.yml** - Control frontend egress (backend + DNS only)
5. **05-backend-egress-policy.yml** - Control backend egress (database + DNS only)
6. **06-database-egress-policy.yml** - Database egress (DNS only, no outbound connections)
7. **07-production-namespace-isolation.yml** - Isolate production namespace

## Step 6: Verify Security Controls

Now let's re-run our tests to confirm the NetworkPolicies are working.

### Test 1: Frontend → Backend (Should Still Work ✅)

Legitimate traffic should still work:

```bash
kubectl exec -it deployment/frontend -- curl -s http://backend:8080
```

<details>
<summary>📋 Expected Output</summary>

```
{"status":"healthy","service":"backend-api"}
```

✅ **PASS** - Legitimate traffic still flows correctly.

</details>

### Test 2: Backend → Database (Should Still Work ✅)

```bash
kubectl exec -it deployment/backend -- nc -zv database 5432
```

<details>
<summary>📋 Expected Output</summary>

```
database (10.x.x.x:5432) open
```

✅ **PASS** - Backend can still access database as needed.

</details>

### Test 3: Frontend → Database (Should Be BLOCKED 🚫)

This attack should now be prevented:

```bash
kubectl exec -it deployment/frontend -- nc -zv -w 5 database 5432
```

<details>
<summary>📋 Expected Output</summary>

```
nc: database (10.x.x.x:5432): Operation timed out
command terminated with exit code 1
```

✅ **BLOCKED** - Attack prevented! Frontend cannot bypass backend anymore.

</details>

### Test 4: Egress to Internet (Should Be BLOCKED 🚫)

Data exfiltration should now be blocked:

```bash
kubectl exec -it deployment/frontend -- curl -s -I https://google.com --connect-timeout 5
```

<details>
<summary>📋 Expected Output</summary>

```
curl: (28) Connection timed out after 5001 milliseconds
command terminated with exit code 28
```

✅ **BLOCKED** - Egress to internet is blocked, preventing data exfiltration.

</details>

### Test 5: Cross-Namespace Access (Should Be BLOCKED 🚫)

```bash
kubectl exec -it deployment/frontend -- curl -s http://prod-app.production.svc.cluster.local --connect-timeout 5
```

<details>
<summary>📋 Expected Output</summary>

```
curl: (28) Connection timed out after 5000 milliseconds
command terminated with exit code 28
```

✅ **BLOCKED** - Cross-namespace access is prevented by namespace isolation policy.

</details>

### Test 6: DNS Still Works ✅

Verify that DNS resolution still works (we explicitly allowed it):

```bash
kubectl exec -it deployment/frontend -- nslookup backend
```

<details>
<summary>📋 Expected Output</summary>

```
Server:    10.x.x.x
Address 1: 10.x.x.x kube-dns.kube-system.svc.cluster.local

Name:      backend
Address 1: 10.x.x.x backend.default.svc.cluster.local
```

✅ **PASS** - DNS resolution works because we explicitly allowed UDP:53 to kube-system.

</details>

## What We've Prevented

### ✅ Lateral Movement Attacks
- Frontend can no longer bypass backend to access database
- Each tier can only communicate with authorized adjacent tiers
- Compromised frontend has limited blast radius

### ✅ Data Exfiltration
- Egress traffic is tightly controlled
- Pods cannot reach arbitrary external endpoints
- Only necessary egress (DNS) is allowed

### ✅ Namespace Escape
- Production namespace is isolated from default namespace
- Multi-tenant environments are properly segmented
- Workloads cannot probe/attack other namespaces

### ✅ Zero-Trust Networking
- Default deny all traffic
- Explicitly allow only legitimate communication paths
- Defense-in-depth security posture

## NetworkPolicy Security Levels

Here's a progression of NetworkPolicy implementations from least to most secure:

| Level | Description | Security Impact |
|-------|-------------|-----------------|
| **Level 0** | No NetworkPolicies | ❌ Cluster-wide unrestricted network access |
| **Level 1** | Default deny ingress | 🟡 Blocks pod-to-pod ingress, but egress still open |
| **Level 2** | Ingress + explicit allow rules | 🟢 Controls north-south traffic within cluster |
| **Level 3** | Ingress + Egress policies | 🟢 Controls both ingress and egress, prevents data exfiltration |
| **Level 4** | Full zero-trust + namespace isolation | ✅ Complete network segmentation and isolation |

**This exercise brings you from Level 0 → Level 4!**

## Bonus: Advanced Scenarios

### Scenario 1: Allow External API Access

What if your backend needs to call an external API (e.g., payment processor)?

<details>
<summary>💡 Solution</summary>

Add a CIDR-based egress rule:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-external-api
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 203.0.113.0/24  # Payment processor IP range
    ports:
    - protocol: TCP
      port: 443
```

This allows backend to reach specific external IPs on port 443 (HTTPS).

</details>

### Scenario 2: Allow Health Checks from Ingress Controller

<details>
<summary>💡 Solution</summary>

Add ingress rule for ingress controller namespace:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-ingress-controller
spec:
  podSelector:
    matchLabels:
      tier: frontend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 80
```

</details>

### Scenario 3: Allow Monitoring from Prometheus

<details>
<summary>💡 Solution</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-prometheus-scraping
spec:
  podSelector: {}  # All pods
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    - podSelector:
        matchLabels:
          app: prometheus
    ports:
    - protocol: TCP
      port: 9090  # Metrics port
```

</details>

## Cleanup

Remove all resources created in this exercise:

```bash
# Delete application resources
kubectl delete -f start/

# Delete network policies
kubectl delete -f done/

# Delete test resources
kubectl delete namespace production --ignore-not-found
```

## Important Notes

### CNI Requirements

NetworkPolicies require a CNI plugin that supports them. Check your cluster:

```bash
# Check if NetworkPolicies are available
kubectl api-resources | grep networkpolicies

# Check your CNI (look for calico, cilium, weave, etc.)
kubectl get pods -n kube-system
```

**Common CNI Plugins:**
- ✅ **Calico** - Full NetworkPolicy support
- ✅ **Cilium** - Full NetworkPolicy support + eBPF
- ✅ **Weave Net** - Full NetworkPolicy support
- ⚠️ **Flannel** - No NetworkPolicy support (use Canal for Flannel + Calico)
- ❌ **kubenet** - No NetworkPolicy support

### Common Pitfalls

1. **Forgetting DNS**
   - Pods need DNS to resolve service names
   - Always allow UDP:53 to kube-system namespace
   
2. **Debugging connectivity issues**
   - Use `kubectl logs` to check for connection timeouts
   - Verify pod labels match NetworkPolicy selectors: `kubectl get pods --show-labels`
   
3. **Order matters**
   - Apply default-deny first, then allow rules
   - Pods without matching allow rules will be blocked
   
4. **Testing with `curl`**
   - Always use `--connect-timeout` to avoid hanging
   - Check return codes: 0 = success, 28 = timeout

## Key Takeaways

1. **NetworkPolicies are namespace-scoped** - Each namespace needs its own policies
2. **Default deny is essential** - Start with blocking everything, then allow explicitly
3. **Labels are critical** - NetworkPolicies use labels to select pods
4. **Ingress ≠ Egress** - Control both directions for complete security
5. **NetworkPolicies are additive** - Multiple policies can apply to the same pod
6. **DNS is often forgotten** - Remember to allow DNS (UDP:53 to kube-system)
7. **Test thoroughly** - Verify both legitimate traffic works AND attacks are blocked

## Next Steps

Now that you understand NetworkPolicies, consider:

1. **Combine with PodSecurityPolicies/PodSecurityAdmission** - Multi-layered defense
2. **Implement service mesh** (Istio, Linkerd) - Adds mTLS and more granular policies
3. **Use OPA/Gatekeeper** - Policy-as-code for automated governance
4. **Monitor network traffic** - Use tools like Cilium Hubble or Calico observability
5. **Implement network policies in CI/CD** - Automate security from the start

## Further Reading

- [Kubernetes NetworkPolicy Documentation](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [NetworkPolicy Recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes)
- [Calico NetworkPolicy Tutorial](https://docs.projectcalico.org/security/kubernetes-network-policy)
- [CNCF Network Policy WG](https://github.com/kubernetes/community/tree/master/sig-network)
- [Zero Trust Networks (Book)](https://www.oreilly.com/library/view/zero-trust-networks/9781491962183/)

## Troubleshooting Guide

### Issue: NetworkPolicies not enforced

**Symptoms:** Connections that should be blocked still work

**Solutions:**
1. Verify CNI supports NetworkPolicies: `kubectl get pods -n kube-system`
2. Check policies are created: `kubectl get networkpolicies`
3. Verify pod labels: `kubectl get pods --show-labels`
4. Check policy selectors match pod labels

### Issue: Legitimate traffic blocked

**Symptoms:** Application cannot communicate with dependencies

**Solutions:**
1. Check if default-deny is in place without allow rules
2. Verify allow rules target correct pods (check labels)
3. Ensure ports match: `kubectl get svc <service-name> -o yaml`
4. Check for typos in namespace/pod selectors

### Issue: DNS not working

**Symptoms:** Pods cannot resolve service names

**Solutions:**
```bash
# Test DNS
kubectl exec -it deployment/frontend -- nslookup kubernetes.default

# Check DNS policy
kubectl get networkpolicies -o yaml | grep -A 10 "port: 53"

# Verify kube-system namespace label
kubectl get namespace kube-system --show-labels
```

Add DNS egress rule:
```yaml
egress:
- to:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: kube-system
  ports:
  - protocol: UDP
    port: 53
```

### Issue: Cannot test from pods

**Symptoms:** `kubectl exec` fails or tools missing

**Solutions:**
```bash
# Use a debug container
kubectl debug -it deployment/frontend --image=nicolaka/netshoot -- /bin/bash

# Or deploy a test pod
kubectl run test-pod --image=nicolaka/netshoot -it --rm -- /bin/bash
```

### Issue: Policies not showing up

**Symptoms:** `kubectl get networkpolicies` returns nothing

**Solutions:**
1. Check you're in the correct namespace: `kubectl config get-contexts`
2. Policies are namespace-scoped: `kubectl get networkpolicies -A`
3. Verify YAML is valid: `kubectl apply -f policy.yaml --dry-run=client`

---

**Congratulations!** You've successfully implemented zero-trust networking with Kubernetes NetworkPolicies. You now understand how to prevent lateral movement, data exfiltration, and namespace escape attacks through proper network segmentation.
