# RBAC Service Account

## Learning Objectives

In this exercise, you will:
- Understand how Role, RoleBinding, and ServiceAccount work together
- See the danger of overly-permissive RBAC in action
- Apply least-privilege RBAC to lock down access
- Debug RBAC issues using `kubectl auth can-i`

## Exercise Pattern

1. **Deploy overly-permissive RBAC** → See it work
2. **Exploit the permissions** → See dangerous operations succeed (bad!)
3. **Apply least-privilege RBAC** → Modify the Role manifest
4. **Test the same operations** → See them blocked (good!)

---

## Step 1: Set Up the Environment

Deploy the seed resources that will serve as exploit targets:

```bash
kubectl apply -f start/seed-secret.yaml
kubectl apply -f start/seed-pod.yaml
```

The Secret (`db-credentials`) contains dummy database credentials. The pod (`seed-pod`) is a running workload that the overly-permissive ServiceAccount will be able to destroy.

Wait for the seed pod to be ready:

```bash
kubectl wait --for=condition=ready pod/seed-pod --timeout=60s
```

---

## Step 2: Deploy the Overly-Permissive RBAC

Apply the ServiceAccount, Role, RoleBinding, and attacker pod:

```bash
kubectl apply -f start/service-account.yaml
kubectl apply -f start/role.yaml
kubectl apply -f start/rolebinding.yaml
kubectl apply -f start/pod.yaml
```

Wait for the attacker pod to be ready:

```bash
kubectl wait --for=condition=ready pod/rbac-demo --timeout=60s
```

This deploys a ServiceAccount (`rbac-demo-sa`) bound to a Role (`overly-permissive`) that grants broad access to secrets, pods, and configmaps. The pod (`rbac-demo`) runs with that ServiceAccount, giving us a shell from which to exercise those permissions.

---

## Step 3: Exploit the Permissions (The Bad Phase)

Now let's see what this ServiceAccount can do. These tests simulate real attacker behavior.

Exec into the pod:

```bash
kubectl exec -it rbac-demo -- /bin/sh
```

### Test 1: Read the database credentials

```bash
kubectl get secret db-credentials -o yaml
```

<details>
<summary>Expected output</summary>

```yaml
apiVersion: v1
data:
  password: c3VwZXItc2VjcmV0LXBhc3N3b3Jk
  username: YWRtaW4=
kind: Secret
metadata:
  name: db-credentials
  namespace: default
type: Opaque
```

**Problem:** The ServiceAccount can read any Secret in the namespace. An attacker can base64-decode the password (`echo 'c3VwZXItc2VjcmV0LXBhc3N3b3Jk' | base64 -d`) and steal the database credentials.
</details>

### Test 2: Destroy the seed pod

```bash
kubectl delete pod seed-pod
```

<details>
<summary>Expected output</summary>

```
pod "seed-pod" deleted
```

**Problem:** The ServiceAccount can delete any pod in the namespace. This is a denial-of-service attack — a compromised workload can tear down other workloads.
</details>

### Test 3: Create unauthorized resources

```bash
kubectl create configmap test-cm --from-literal=key=value
```

<details>
<summary>Expected output</summary>

```
configmap/test-cm created
```

**Problem:** The ServiceAccount can create resources in the namespace. An attacker could use this for data exfiltration staging, storing command-and-control configuration, or establishing persistence.
</details>

When you are done, exit the pod shell:

```bash
exit
```

---

## Step 4: Apply Least-Privilege RBAC

### Your Task

Edit `start/role.yaml` and change the Role so it only grants:
- verbs: `get`, `list`
- resources: `pods`

Remove access to `secrets` and `configmaps` entirely. The application only needs to list pods (for example, for a health-check sidecar). It has no legitimate reason to read secrets, delete pods, or create configmaps.

<details>
<summary>Hint: What the Role spec should look like</summary>

```yaml
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
```
</details>

<details>
<summary>Hint: Why this is least-privilege</summary>

RBAC permissions are additive — there is no explicit deny. If a verb is not listed, it is denied by default. By granting only `get` and `list` on `pods`, the ServiceAccount:

- Cannot read Secrets (no credential theft)
- Cannot delete pods (no workload disruption)
- Cannot create any resources (no persistence or exfiltration staging)
- Can still perform its legitimate function: listing pods

This is the principle of least privilege applied to Kubernetes identities.
</details>

---

## Step 5: Redeploy and Verify

First, clean up the resources created during the exploit phase:

```bash
kubectl delete configmap test-cm --ignore-not-found
```

Delete the old Role and attacker pod, then redeploy with the updated Role:

```bash
kubectl delete -f start/role.yaml
kubectl delete pod rbac-demo
kubectl apply -f start/role.yaml
kubectl apply -f start/pod.yaml
kubectl wait --for=condition=ready pod/rbac-demo --timeout=60s
```

Re-create the seed pod that was deleted in Step 3:

```bash
kubectl apply -f start/seed-pod.yaml
```

Now exec into the pod again:

```bash
kubectl exec -it rbac-demo -- /bin/sh
```

### Test 1: Try to read the secret (should fail)

```bash
kubectl get secret db-credentials -o yaml
```

<details>
<summary>Expected output</summary>

```
Error from server (Forbidden): secrets "db-credentials" is forbidden:
User "system:serviceaccount:default:rbac-demo-sa"
cannot get resource "secrets" in API group "" in the namespace "default"
```

**Success!** The ServiceAccount can no longer read Secrets. Credentials are protected.
</details>

### Test 2: Try to delete a pod (should fail)

```bash
kubectl delete pod seed-pod
```

<details>
<summary>Expected output</summary>

```
Error from server (Forbidden): pods "seed-pod" is forbidden:
User "system:serviceaccount:default:rbac-demo-sa"
cannot delete resource "pods" in API group "" in the namespace "default"
```

**Success!** The ServiceAccount can no longer delete pods. Workloads are protected from disruption.
</details>

### Test 3: Try to create a configmap (should fail)

```bash
kubectl create configmap test-cm --from-literal=key=value
```

<details>
<summary>Expected output</summary>

```
Error from server (Forbidden): configmaps is forbidden:
User "system:serviceaccount:default:rbac-demo-sa"
cannot create resource "configmaps" in API group "" in the namespace "default"
```

**Success!** The ServiceAccount can no longer create resources. Persistence and exfiltration paths are closed.
</details>

### Bonus: Verify scoped access still works

```bash
kubectl get pods
```

<details>
<summary>Expected output</summary>

```
NAME         READY   STATUS    RESTARTS   AGE
rbac-demo    1/1     Running   0          2m
seed-pod     1/1     Running   0          1m
```

**Success!** The ServiceAccount can still list pods — its one legitimate use case continues to work.
</details>

Exit the pod shell:

```bash
exit
```

---

## Step 6: RBAC Debugging Tools

### 1. Check what a ServiceAccount can do

Use `kubectl auth can-i` with `--as` to impersonate a ServiceAccount and test specific permissions:

```bash
kubectl auth can-i get secrets --as=system:serviceaccount:default:rbac-demo-sa
kubectl auth can-i delete pods --as=system:serviceaccount:default:rbac-demo-sa
kubectl auth can-i get pods --as=system:serviceaccount:default:rbac-demo-sa
```

> **Note:** Replace `default` with your actual namespace if you are not using the default namespace.

### 2. List all permissions for a ServiceAccount

```bash
kubectl auth can-i --list --as=system:serviceaccount:default:rbac-demo-sa
```

This prints every resource/verb combination the ServiceAccount is permitted to use — useful for auditing.

### 3. Reading RBAC denial errors

When a request is denied, the error message contains everything you need to diagnose the problem:

```
Error from server (Forbidden): secrets "db-credentials" is forbidden:
  User "system:serviceaccount:default:rbac-demo-sa"
  cannot get resource "secrets"
  in API group ""
  in the namespace "default"
```

| Part | Meaning |
|------|---------|
| `system:serviceaccount:default:rbac-demo-sa` | The identity that was denied (namespace + ServiceAccount name) |
| `cannot get resource "secrets"` | The verb and resource that was attempted |
| `in API group ""` | The API group (`""` = core API group) |
| `in the namespace "default"` | The namespace scope of the denial |

---

## Step 7: Compare with Reference Solution

```bash
diff start/role.yaml done/role.yaml
```

Or view the complete solution:

```bash
cat done/role.yaml
```

---

## What We've Prevented

### Attack Vector 1: Credential Theft
- **Before:** The ServiceAccount could read any Secret in the namespace — database passwords, API keys, TLS certificates
- **After:** The ServiceAccount has no access to Secrets

### Attack Vector 2: Workload Disruption
- **Before:** The ServiceAccount could delete any pod in the namespace — a denial-of-service attack against the application
- **After:** The ServiceAccount cannot delete pods

### Attack Vector 3: Persistence and Exfiltration
- **Before:** The ServiceAccount could create ConfigMaps and other resources — useful for attacker persistence or staging data for exfiltration
- **After:** The ServiceAccount cannot create any resources

---

## Cleanup

```bash
kubectl delete -f start/
```

> **Note:** If you re-created `seed-pod` during Step 5, it will be deleted here too. The `test-cm` ConfigMap created during Step 3 (before the fix) will also be removed.

---

## Key Takeaways

- **Principle of least privilege**: only grant the minimum permissions an application actually needs
- **ServiceAccounts are identities**: every pod gets one — make sure it is scoped correctly
- **Roles are additive**: there is no "deny" — if a permission is not granted, it is denied by default
- **`kubectl auth can-i`** is your best friend for debugging RBAC
- **Namespace scope**: Roles and RoleBindings are namespace-scoped — use ClusterRole/ClusterRoleBinding only when truly needed
- **Audit regularly**: review what permissions each ServiceAccount has, especially after Role changes

---

## Further Reading

- [Kubernetes RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#kubectl-auth-reconcile)
- [Service Accounts](https://kubernetes.io/docs/concepts/security/service-accounts/)
- [Good Practices for Kubernetes Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)
