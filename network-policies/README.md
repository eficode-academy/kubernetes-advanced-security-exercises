# Network Policy Security Exercise

## Learning Objectives

By completing this exercise, you will learn:

- How to implement **zero-trust networking** principles in Kubernetes
- How to use **NetworkPolicies** to prevent unauthorized network traffic
- How to enforce **network segmentation** between application tiers
- How to control **egress traffic** to prevent data exfiltration
- How to test and verify network security controls

## Exercise Pattern

This exercise follows a hands-on, attack-then-defend approach:

1. **Deploy insecure configuration** - Set up a 3-tier application without network policies
2. **Test exploits** - Demonstrate unauthorized access and data exfiltration attacks
3. **Understand the threat model** - Learn what attackers can do
4. **Apply security controls** - Implement NetworkPolicies to block attacks
5. **Verify defenses** - Confirm attacks are now prevented

## Architecture Overview

We'll deploy a typical 3-tier Python Flask application:

```
┌─────────────┐
│   Frontend  │  (quotes-flask-frontend)
│  Port: 5000 │
└──────┬──────┘
       │
       │ Should only talk to Backend
       │
       ▼
┌─────────────┐
│   Backend   │  (quotes-flask-backend)
│  Port: 5000 │
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
- ❌ Pods from your namespace can access pods in other namespaces (namespace escape!)

**With NetworkPolicies:**
- ✅ Frontend → Backend only
- ✅ Backend → Database only
- ✅ Controlled egress (DNS only where needed)
- ✅ Namespace isolation

## Prerequisites

- A Kubernetes cluster with a CNI that supports NetworkPolicies.

- To check if NetworkPolicies are supported:
```bash
kubectl api-resources | grep networkpolicies
```

> **Your namespace:** Your namespace is `student-n`, where `n` is the number of your workstation. For example, if you are on **workstation-1**, your namespace is **student-1**. You are in your correct namespace by default.

## Step 1: Deploy Insecure Configuration

First, let's deploy our 3-tier application **without** any NetworkPolicies.

- Deploy all components
```bash
kubectl apply -f quotes-flask/
```

Expected Output:

```text
configmap/backend-config created
deployment.apps/backend created
service/backend created
deployment.apps/frontend created
service/frontend created
configmap/postgres-config created
deployment.apps/postgres created
persistentvolumeclaim/postgres-pvc created
secret/postgres-secret created
service/postgres created
```

- Verify that the deployments are created
```bash
kubectl get deployments
```

Expected Output:

```text
NAME                        READY   STATUS    RESTARTS   AGE
backend-xxxxxxxxx-xxxxx     1/1     Running   0          30s
postgres-xxxxxxxxx-xxxxx    1/1     Running   0          30s
frontend-xxxxxxxxx-xxxxx    1/1     Running   0          30s
```

## Step 2: Test Connectivity (No Network Policies)

Now let's test the connectivity **before** applying NetworkPolicies to see the security issues.

### Test 1: Frontend → Backend (Legitimate Traffic ✅)

This is normal application traffic and should work:

```bash
kubectl exec -it deployment/frontend -- curl -s http://backend:5000
```

Expected Output:

```text
Hello from the backend!
```

✅ **PASS** - Frontend can reach backend as expected.


### Test 2: Backend → Database (Legitimate Traffic ✅)

The backend needs to access the postgres database - this is legitimate:

```bash
kubectl exec -it deployment/backend -- nc -zv postgres 5432
```

Expected Output:

```text
postgres (10.x.x.x:5432) open
```

✅ **PASS** - Backend can reach database as expected.

### Test 3: Frontend → Database (ATTACK! ❌)

**This is a security issue!** The frontend should NOT be able to bypass the backend and access the database directly. This enables:
- SQL injection attacks from compromised frontend
- Data exfiltration
- Unauthorized access

```bash
kubectl exec -it deployment/frontend -- nc -zv postgres 5432
```

Expected Output (Before Network Policies):

```text
postgres (10.x.x.x:5432) open
```

❌ **SECURITY ISSUE** - Frontend can directly access database, bypassing backend logic!


### Test 4: Egress to Internet (Data Exfiltration Risk ❌)

Without egress controls, compromised pods can exfiltrate data:

```bash
kubectl exec -it deployment/frontend -- curl -s -I https://www.google.com --connect-timeout 5
```

Expected Output (Before Network Policies):

```text
HTTP/2 200
content-type: text/html; charset=ISO-8859-1
...
```

❌ **SECURITY ISSUE** - Pods can reach external internet without restriction!


### Test 5: Cross-Namespace Access (Namespace Escape ❌)

Connect to a pod from another namespace to test cross-namespace access:

- Try to access frontend from student-0 namespace
```bash
kubectl exec -it deployment/frontend -- curl -s http://frontend.student-0.svc.cluster.local:5000 --connect-timeout 5
```

Expected Output (Before Network Policies):

```html
<!DOCTYPE html>
<html>
  <head>
    <title>Programming Quotes</title>
...
```

❌ **SECURITY ISSUE** - Pods can access services in other namespaces without restriction!

</details>

## Step 3: Understand the Threat Model

### Attack Vectors

1. **Unauthorized Access**
   - Compromised frontend pod → Direct database access
   - Bypass backend validation and business logic
   - SQL injection, data theft

2. **Data Exfiltration**
   - Any pod can reach external internet
   - Attacker can send stolen credentials/ data out
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

## Step 4: Apply NetworkPolicies Incrementally

Apply **one policy at a time**, verify the behavior at each step, and fill in the missing sections as instructed.

> **How this works:** The `start/` directory contains partially filled policy files - some sections are intentionally left empty for you to complete. If you get stuck, the fully completed versions are in the `done/` directory.

---

### 4.1 Apply `default-deny-all.yaml`

This file is pre-filled. It denies **all ingress and egress** to every pod in the namespace, but allows DNS so service name lookups still work.

```bash
kubectl apply -f start/default-deny-all.yaml
kubectl get networkpolicies
```

Verify - all traffic should now be blocked:

- Frontend → Backend: BLOCKED
```bash
kubectl exec -it deployment/frontend -- curl -sS --connect-timeout 5 http://backend:5000
```

- Frontend → Internet: BLOCKED
```bash
kubectl exec -it deployment/frontend -- curl -s -I https://www.google.com --connect-timeout 5
```

- DNS: should still WORK
```bash
kubectl exec -it deployment/frontend -- nslookup backend
```

Expected:
- Frontend → Backend: timeout ❌
- Frontend → Internet: timeout ❌
- DNS: resolves successfully ✅

---

### 4.2 Apply `frontend-netpol.yaml`

Open `start/frontend-netpol.yaml`. The ingress section is pre-filled (allows inbound traffic on port 5000). The egress section is empty.

**Your task:** Fill in the egress section to allow `frontend` to reach `backend` on port 5000.

<details>
<summary>💡 Hint</summary>

```yaml
egress:
- to:
  - podSelector:
      matchLabels:
        app: backend
  ports:
  - protocol: TCP
    port: 5000
```

</details>

Once filled in, apply:

```bash
kubectl apply -f start/frontend-netpol.yaml
```

Verify:

- Frontend → Backend: still BLOCKED (backend has no ingress rule yet)
```bash
kubectl exec -it deployment/frontend -- curl -sS --connect-timeout 5 http://backend:5000
```

- Frontend → Internet: BLOCKED ✅
```bash
kubectl exec -it deployment/frontend -- curl -s -I https://www.google.com --connect-timeout 5
```

- Frontend → Postgres: BLOCKED ✅ (egress only allows backend, not postgres)
```bash
kubectl exec -it deployment/frontend -- nc -zv -w 5 postgres 5432
```

Expected output:
```text
nc: postgres (10.x.x.x:5432): Operation timed out
command terminated with exit code 1
```

Expected:
- Frontend → Backend: blocked ❌ (both sides need matching rules)
- Frontend → Internet: blocked ✅
- Frontend → Postgres: blocked ✅ (egress rule only permits traffic to `app: backend`)

> Egress permission on the sender alone is not enough - the receiver also needs a matching ingress rule. Also note that even though postgres is in the same namespace, the frontend egress policy only permits `app: backend`, so postgres is unreachable from frontend regardless.


### 4.3 Apply `backend-netpol.yaml`

Open `start/backend-netpol.yaml`. The ingress section is pre-filled (allows ingress from `frontend` on port 5000). The egress section is empty and commented out.

**Step 1:** Apply the file as-is first (ingress only):

```bash
kubectl apply -f start/backend-netpol.yaml
```

Verify:

- Frontend → Backend: NOW WORKS ✅
```bash
kubectl exec -it deployment/frontend -- curl -s http://backend:5000
```

- Backend → Postgres: BLOCKED (no egress rule yet)
```bash
kubectl exec -it deployment/backend -- nc -zv -w 5 postgres 5432
```

Expected:
- Frontend → Backend: allowed ✅
- Backend → Postgres: timeout ❌

**Step 2:** Now uncomment and fill in the egress section to allow `backend` to reach `postgres` on port 5432.

<details>
<summary>💡 Hint</summary>

```yaml
egress:
- to:
  - podSelector:
      matchLabels:
        app: postgres
  ports:
  - protocol: TCP
    port: 5432
```

</details>

Apply again:

```bash
kubectl apply -f start/backend-netpol.yaml
```

Verify:

- Backend → Postgres: still BLOCKED (postgres has no ingress rule yet)
```bash
kubectl exec -it deployment/backend -- nc -zv -w 5 postgres 5432
```

- Frontend → Backend: still WORKS ✅
```bash
kubectl exec -it deployment/frontend -- curl -s http://backend:5000
```

Expected:
- Backend → Postgres: still blocked ❌ (postgres needs its own ingress rule)
- Frontend → Backend: allowed ✅

---

### 4.4 Apply `postgres-netpol.yaml`

This file is pre-filled. It allows ingress from `backend` on port 5432.

```bash
kubectl apply -f start/postgres-netpol.yaml
```

Verify:

- Backend → Postgres: NOW WORKS ✅
```bash
kubectl exec -it deployment/backend -- nc -zv postgres 5432
```

- Frontend → Postgres: still BLOCKED ✅ (attack path closed!)
```bash
kubectl exec -it deployment/frontend -- nc -zv -w 5 postgres 5432
```

Expected output (backend → postgres):

```text
postgres (10.x.x.x:5432) open
```

Expected output (frontend → postgres):

```text
nc: postgres (10.x.x.x:5432): Operation timed out
command terminated with exit code 1
```

- Backend → Postgres: allowed ✅
- Frontend → Postgres: blocked ✅

---

### 4.5 Test Cross-Namespace Access (Namespace Escape ❌)

No new policy file is needed here. This test verifies that the policies already applied prevent cross-namespace access.

From your frontend pod, try to reach the frontend service in another namespace:

- For example, let's try student-0 namespace
```bash
kubectl exec -it deployment/frontend -- curl -sS http://frontend.student-0.svc.cluster.local:5000 --connect-timeout 5
```

Expected output:
```text
curl: (28) Failed to connect to frontend.student-0.svc.cluster.local port 5000 after 5000 ms: Timeout was reached
command terminated with exit code 28
```

Expected:
- Frontend → other namespace frontend: timeout ❌

> This is blocked by the `frontend-netpol` egress rule: it only permits traffic to `app: backend` within the same namespace. No egress rule allows traffic to other namespaces, so cross-namespace connections time out regardless of what policies exist in the target namespace.

**Challenge: Can others reach your frontend?**

The current ingress rule in `frontend-netpol.yaml` has no `from:` field, which means it allows traffic from **any pod in any namespace** on port 5000. Ask a neighbour to try reaching your frontend:

- From a neighbour's namespace - replace <your-namespace> with your actual namespace
```bash
kubectl exec -it deployment/frontend -- curl -sS http://frontend.<your-namespace>.svc.cluster.local:5000 --connect-timeout 5
```

It will succeed! Now fix it by adding a `from:` field to restrict ingress to only pods within your own namespace.

<details>
<summary>💡 Hint</summary>

```yaml
ingress:
- from:
  - podSelector: {}   # empty podSelector = any pod in THIS namespace only
  ports:
  - protocol: TCP
    port: 5000
```

</details>

Apply and verify:

```bash
kubectl apply -f start/frontend-netpol.yaml
```

- Neighbour's pod → Your frontend: now BLOCKED ✅
- Your own pods → Your frontend: still WORKS ✅
```bash
kubectl exec -it deployment/backend -- curl -s http://frontend:5000 --connect-timeout 5
```

## Step 5: Final Validation (All Policies Applied)

Run the full test set to confirm the final state:

- Legitimate traffic: should WORK
```bash
kubectl exec -it deployment/frontend -- curl -s http://backend:5000

kubectl exec -it deployment/backend -- nc -zv postgres 5432
```

- Attack paths: should be BLOCKED
```bash
kubectl exec -it deployment/frontend -- nc -zv -w 5 postgres 5432

kubectl exec -it deployment/frontend -- curl -s -I https://www.google.com --connect-timeout 5

kubectl exec -it deployment/frontend -- curl -s http://frontend.student-0.svc.cluster.local:5000 --connect-timeout 5
```

- DNS: should still WORK
```bash
kubectl exec -it deployment/frontend -- nslookup backend
```

Expected final state:
- ✅ Frontend → Backend: allowed
- ✅ Backend → Postgres: allowed
- ✅ Frontend → Postgres: blocked (attack path closed)
- ✅ Frontend → Internet: blocked (no data exfiltration)
- ✅ Frontend → other namespaces: blocked (namespace isolation)
- ✅ Other namespace pods → Frontend: blocked (after challenge fix in 4.5)
- ✅ DNS: works

## Step 6: What You Observed

By applying one policy at a time, you can clearly see:
1. Default deny creates the zero-trust baseline.
2. Allow rules restore only required app flows.
3. Egress rules stop data exfiltration.
4. Namespace isolation adds tenant boundary protection.

## Step 7: What We've Prevented

### ✅ Unauthorized Access
- Frontend can no longer bypass backend to access the database directly
- Each tier can only communicate with its authorized adjacent tier
- Compromised frontend has limited blast radius

### ✅ Data Exfiltration
- Egress traffic is tightly controlled
- Pods cannot reach arbitrary external endpoints
- Only necessary egress (DNS) is allowed

### ✅ Namespace Escape
- Your frontend cannot reach pods in other namespaces (egress restricted)
- Pods in other namespaces cannot reach your frontend (ingress restricted with `from: podSelector: {}`)
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

**Congratulations!** You've successfully implemented zero-trust networking with Kubernetes NetworkPolicies. You now understand how to prevent unauthorized access, data exfiltration, and namespace escape attacks through proper network segmentation.