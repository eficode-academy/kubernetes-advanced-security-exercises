# Pod Security Standards

> **Prerequisite:** Complete the [Pod Security Context](../pod-security-context/pod-security-context.md) exercise before starting this one. This exercise builds directly on what you learned there.

## Learning Objectives

In this exercise, you will:
- Understand why per-pod security context alone is not enough to protect a namespace
- Learn how Pod Security Standards (PSS) enforce security policies at the admission control level
- Apply Pod Security Admission (PSA) labels to enforce the `restricted` security profile on your namespace
- Verify that non-compliant pods are rejected at admission time, while your hardened pod continues to work

## The Gap Security Context Doesn't Fill

In the previous exercise, you hardened a pod's security context. That pod is now secure. But nothing stops another developer — or an attacker with `kubectl` access — from deploying a brand new privileged pod right next to it.

Security context is **developer-enforced**: it only applies to pods that include it. Pod Security Admission is **cluster-enforced**: it rejects any pod that violates the policy, regardless of who deploys it.

## Exercise Pattern

1. **Deploy your hardened pod** → Confirm it still runs correctly
2. **Demonstrate the gap** → Show that a privileged pod can still be deployed without PSA
3. **Apply PSA labels** → Enforce the `restricted` profile on the namespace
4. **Verify** → Confirm non-compliant pods are rejected and your hardened pod still works

---

## Step 1: Deploy the Hardened Pod

The pod in `start/pod.yaml` is already hardened — it represents the output of the Pod Security Context exercise.

Deploy it:

```bash
kubectl apply -f start/pod.yaml
kubectl wait --for=condition=Ready pod/pss-demo --timeout=60s
```

Confirm it is running as a non-root user with no capabilities:

```bash
kubectl exec pss-demo -- id
```

<details>
<summary>Expected output</summary>

```
uid=1000 gid=1000 groups=1000
```

Good — your hardened pod is working correctly.
</details>

---

## Step 2: Demonstrate the Gap

Even though your pod is hardened, anyone with access to your namespace can still deploy a privileged pod. Try it:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: privileged-test
spec:
  containers:
  - name: test
    image: nginx:1.27
    securityContext:
      privileged: true
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
      limits:
        memory: "128Mi"
        cpu: "200m"
EOF
```

<details>
<summary>Expected output</summary>

```
pod/privileged-test created
```

**Problem:** The privileged pod was accepted! Without PSA labels on the namespace, Kubernetes admits any pod regardless of how dangerous its configuration is. Your hardened pod and this privileged pod now exist side by side.
</details>

Clean up the test pod before continuing:

```bash
kubectl delete pod privileged-test
```

---

## Step 3: Check Namespace-Level Enforcement

> Note: Replace `student-0` with your namespace name.

```bash
kubectl get namespace student-0 -o jsonpath='{.metadata.labels}' | grep pod-security
```

<details>
<summary>Expected output</summary>

```
(no output)
```

**Problem:** No Pod Security Admission labels are in place, so the namespace has no enforcement policy.
</details>

---

## Step 4: Apply Pod Security Admission Labels

Your task is to edit `start/namespace.yaml` to add PSA labels that enforce, warn, and audit the `restricted` profile.

> Fill in your namespace name under `metadata.name` and `metadata.labels.name`.

PSA supports three independent modes that can be used together:
- **`enforce`** — rejects pods that violate the policy (hard block)
- **`warn`** — shows a warning in `kubectl` output but still admits the pod
- **`audit`** — records violations in the API server audit log

Using all three together gives you enforcement with full visibility.

<details>
<summary>Hint: PSA label format</summary>

```
pod-security.kubernetes.io/<mode>: <level>
pod-security.kubernetes.io/<mode>-version: <version>
```

Where:
- `<mode>` is `enforce`, `warn`, or `audit`
- `<level>` is `restricted`
- `<version>` is `latest`
</details>

<details>
<summary>Hint: Complete namespace example</summary>

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: student-0
  labels:
    name: student-0
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: latest
```
</details>

Apply your updated namespace:

```bash
kubectl apply -f start/namespace.yaml
```

---

## Step 5: Verify Pod Security Admission Is Active

### Verify 1: PSA labels are set on the namespace

> Note: Replace `student-0` with your namespace name.

```bash
kubectl get namespace student-0 -o jsonpath='{.metadata.labels}' | grep -o 'pod-security[^,}]*' | sort
```

<details>
<summary>Expected output</summary>

```
pod-security.kubernetes.io/audit":"restricted"
pod-security.kubernetes.io/audit-version":"latest"
pod-security.kubernetes.io/enforce":"restricted"
pod-security.kubernetes.io/enforce-version":"latest"
pod-security.kubernetes.io/warn":"restricted"
pod-security.kubernetes.io/warn-version":"latest"
```

**Success!** The namespace now enforces the restricted profile.
</details>

### Verify 2: Non-compliant pod is rejected

Try the same privileged pod from Step 2:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: privileged-test
spec:
  containers:
  - name: test
    image: nginx:1.27
    securityContext:
      privileged: true
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
      limits:
        memory: "128Mi"
        cpu: "200m"
EOF
```

<details>
<summary>Expected output</summary>

```
Error from server (Forbidden): error when creating "STDIN": pods "privileged-test" is forbidden: violates PodSecurity "restricted:latest": privileged (container "test" must not set securityContext.privileged=true)
```

**Success!** The API server now blocks non-compliant pods at admission time, before they are ever scheduled or run.
</details>

### Verify 3: Hardened pod still works

Your existing hardened pod should be unaffected:

```bash
kubectl exec pss-demo -- echo "Hello from the secure container"
```

<details>
<summary>Expected output</summary>

```
Hello from the secure container
```

**Success!** A properly configured pod satisfies the restricted profile and continues to run normally.
</details>

### Verify 4: Pod spec confirms compliant configuration

```bash
kubectl get pod pss-demo -o jsonpath='{.spec.containers[0].securityContext.capabilities}'
kubectl get pod pss-demo -o jsonpath='{.spec.securityContext.seccompProfile.type}'
```

<details>
<summary>Expected output</summary>

```
{"drop":["ALL"]}
RuntimeDefault
```

**Success!** The pod's security context matches the requirements of the restricted profile.
</details>

---

## Step 6: Compare with Reference Solution

```bash
diff start/namespace.yaml done/namespace.yaml
```

Or view the reference directly:

```bash
cat done/namespace.yaml
```

---

## The Three PSS Levels

Pod Security Standards define three levels. Your namespace now enforces the strictest one:

| Level | What it allows | Use case |
|---|---|---|
| **privileged** | Unrestricted — any pod configuration | System-level workloads (node agents, CNI plugins) |
| **baseline** | Blocks the most dangerous configurations (privileged mode, host namespaces) | General application workloads migrating from no enforcement |
| **restricted** | Heavily restricted — enforces current security best practices | New workloads; production namespaces |

## What Admission Control Prevents

| Without PSA | With PSA (`restricted`) |
|---|---|
| Any developer can deploy a privileged pod | Privileged pods rejected at the API server |
| hostPath volumes can expose the host filesystem | hostPath volumes blocked |
| host namespace sharing (PID/Network/IPC) can be used | Host namespace sharing blocked |
| Containers can run as root | `runAsNonRoot` required |
| No capability restrictions | All capabilities must be dropped |
| No seccomp profile required | `RuntimeDefault` or stricter required |

---

## Cleanup

```bash
kubectl delete pod pss-demo
```

> **Warning:** Do not delete your namespace — leave the PSA labels in place for subsequent exercises.

---

## Key Takeaways

- **Security context is developer-enforced** — it only protects pods that correctly include it; it cannot prevent other insecure pods from being deployed in the same namespace
- **Pod Security Admission is cluster-enforced** — it applies to every pod admitted to a namespace, regardless of who deploys it
- **The restricted profile is production-ready** — it enforces running as non-root, dropping capabilities, applying seccomp profiles, and blocking host access
- **Use all three modes together** — `enforce` blocks violations, `warn` surfaces them in `kubectl`, and `audit` logs them; together they give you enforcement with full observability
- **Admission control happens early** — violations are caught before the pod is scheduled or run, preventing security incidents before they start
- **PSS complements security context** — they operate at different layers; security context defines what a pod requests, PSA defines what a namespace permits

---

## Next Steps

1. **Audit your existing namespaces** — Check which namespaces lack PSS labels and assess the risk
2. **Use `warn` and `audit` before `enforce`** — In production, use these modes first to understand which workloads would be blocked before introducing hard enforcement
3. **Explore OPA/Gatekeeper** — PSS covers pod-level security; Gatekeeper can enforce organisation-specific requirements beyond what PSS provides
4. **Continue to the Network Policies exercise** — Combine PSS with network segmentation for comprehensive defence in depth

---

## Further Reading

- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)
- [Configure Pod Security Standards for a Namespace](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/)
