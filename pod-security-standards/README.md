# Pod Security Standards

## Learning Objectives

In this exercise, you will:
- Deploy pods with dangerous security configurations in an unrestricted namespace
- Understand how Pod Security Standards (PSS) enforce security policies at the admission control level
- Apply Pod Security Admission (PSA) labels to enforce the restricted security profile
- Modify pod manifests to comply with the restricted Pod Security Standard
- Verify that non-compliant pods are rejected while compliant pods are admitted

## Exercise Pattern

1. **Deploy the insecure configuration** → See it work
2. **Test dangerous operations** → See them succeed (bad!)
3. **Apply security best practices** → Modify the manifests
4. **Test the same operations** → See them fail (good!)

---

## Step 1: Deploy the Baseline Namespace and Pod

First, create the namespace without any Pod Security Standards enforcement:

```bash
kubectl apply -f start/namespace.yml
```

Wait for the namespace to be ready:

```bash
kubectl get namespace pss-test
```

Now deploy the highly privileged pod:

```bash
kubectl apply -f start/pod.yml
```

Wait for the pod to be ready:

```bash
kubectl wait --for=condition=Ready pod/pss-demo -n pss-test --timeout=60s
```

---

## Step 2: Test Security Issues (The Exploit Phase)

The pod we just deployed violates almost every security best practice. Let's explore what makes it dangerous.

### Test 1: Check if pod runs as root

```bash
kubectl exec -n pss-test pss-demo -- id
```

<details>
<summary>Expected output</summary>

```
uid=0(root) gid=0(root) groups=0(root)
```

**Problem:** The container runs as root (UID 0), giving it full privileges inside the container and potential host access through vulnerabilities.
</details>

### Test 2: Verify privileged mode is enabled

```bash
kubectl get pod -n pss-test pss-demo -o jsonpath='{.spec.containers[0].securityContext.privileged}'
```

<details>
<summary>Expected output</summary>

```
true
```

**Problem:** Privileged mode grants the container nearly all capabilities of the host, essentially removing the security boundary between container and host.
</details>

### Test 3: Check dangerous capabilities

```bash
kubectl get pod -n pss-test pss-demo -o jsonpath='{.spec.containers[0].securityContext.capabilities.add}'
```

<details>
<summary>Expected output</summary>

```
["SYS_ADMIN","NET_ADMIN"]
```

**Problem:** SYS_ADMIN and NET_ADMIN capabilities allow system administration tasks and network manipulation, enabling container escape and network hijacking.
</details>

### Test 4: Verify host namespace access

```bash
kubectl get pod -n pss-test pss-demo -o jsonpath='{.spec.hostPID}{"\n"}{.spec.hostNetwork}{"\n"}{.spec.hostIPC}{"\n"}'
```

<details>
<summary>Expected output</summary>

```
true
true
true
```

**Problem:** Access to host namespaces (PID, Network, IPC) allows the container to see and interact with host processes, network interfaces, and shared memory.
</details>

### Test 5: Inspect host processes from inside the container

```bash
kubectl exec -n pss-test pss-demo -- ps aux | head -20
```

<details>
<summary>What you'll see</summary>

```
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.0 168644 13472 ?        Ss   12:00   0:01 /sbin/init
root         2  0.0  0.0      0     0 ?        S    12:00   0:00 [kthreadd]
...
```

**Problem:** With hostPID enabled, the container can see all host processes, making it trivial to identify and potentially manipulate critical system services.
</details>

### Test 6: Access host filesystem

```bash
kubectl exec -n pss-test pss-demo -- ls -la /host/etc/ | head -10
```

<details>
<summary>What you'll see</summary>

```
total 1234
drwxr-xr-x 123 root root  12288 Feb 20 12:00 .
drwxr-xr-x  19 root root   4096 Feb 20 12:00 ..
-rw-r--r--   1 root root   3028 Feb 20 12:00 adduser.conf
drwxr-xr-x   2 root root   4096 Feb 20 12:00 alternatives
...
```

**Problem:** The hostPath volume mount at /host gives the container read/write access to the entire host filesystem, enabling data exfiltration or malicious modification.
</details>

### Test 7: Attempt to modify host filesystem

```bash
kubectl exec -n pss-test pss-demo -- touch /host/tmp/container-was-here
kubectl exec -n pss-test pss-demo -- ls -la /host/tmp/container-was-here
```

<details>
<summary>Expected output</summary>

```
-rw-r--r-- 1 root root 0 Feb 20 12:30 /host/tmp/container-was-here
```

**Problem:** Not only can the container read the host filesystem, it can write to it, allowing deployment of rootkits, backdoors, or data destruction.
</details>

### Test 8: Check privilege escalation setting

```bash
kubectl get pod -n pss-test pss-demo -o jsonpath='{.spec.containers[0].securityContext.allowPrivilegeEscalation}'
```

<details>
<summary>Expected output</summary>

```
true
```

**Problem:** With allowPrivilegeEscalation enabled, processes inside the container can gain more privileges than their parent, potentially exploiting SUID binaries.
</details>

### Test 9: Verify no seccomp profile is applied

```bash
kubectl get pod -n pss-test pss-demo -o jsonpath='{.spec.securityContext.seccompProfile}'
```

<details>
<summary>Expected output</summary>

```
(empty output)
```

**Problem:** Without a seccomp profile, the container can make any system call, vastly increasing the attack surface for kernel exploits.
</details>

### Test 10: Check namespace-level Pod Security Standard enforcement

```bash
kubectl get namespace pss-test -o jsonpath='{.metadata.labels}' | grep pod-security
```

<details>
<summary>Expected output</summary>

```
(empty output or no pod-security labels)
```

**Problem:** Without Pod Security Admission labels on the namespace, Kubernetes will admit any pod regardless of how dangerous its configuration is.
</details>

---

## Step 3: Apply Pod Security Standards

Now it's your turn to harden this configuration. You'll need to:

1. **Add Pod Security Admission labels** to the namespace to enforce the `restricted` profile
2. **Modify the pod manifest** to comply with the restricted Pod Security Standard

### Your Task

1. Update `start/namespace.yml` to add Pod Security Admission labels that enforce, warn, and audit the `restricted` profile
2. Update `start/pod.yml` to remove all dangerous configurations:
   - Remove `hostPID`, `hostNetwork`, and `hostIPC`
   - Remove the `privileged` flag
   - Remove dangerous capabilities
   - Remove the hostPath volume mount
   - Add `runAsNonRoot: true` and set `runAsUser` to a non-zero value
   - Set `allowPrivilegeEscalation: false`
   - Drop all capabilities
   - Add a seccomp profile (`RuntimeDefault`)

<details>
<summary>Hint 1: Namespace labels for Pod Security Admission</summary>

You need to add labels to the namespace metadata in this format:
```
pod-security.kubernetes.io/<mode>: <level>
pod-security.kubernetes.io/<mode>-version: <version>
```

Where `<mode>` can be `enforce`, `warn`, or `audit`, and `<level>` should be `restricted` for maximum security.
</details>

<details>
<summary>Hint 2: Pod security context fields</summary>

At the pod level, you need to set:
- `securityContext.runAsNonRoot`
- `securityContext.runAsUser` (must be non-zero)
- `securityContext.runAsGroup`
- `securityContext.fsGroup`
- `securityContext.seccompProfile.type`

At the container level, you need to set:
- `securityContext.allowPrivilegeEscalation`
- `securityContext.runAsNonRoot`
- `securityContext.capabilities.drop`
- `securityContext.seccompProfile.type`
</details>

<details>
<summary>Hint 3: What to remove from the pod spec</summary>

Remove these entire sections from the pod spec:
```yaml
hostPID: true
hostNetwork: true
hostIPC: true
```

Remove these from the container securityContext:
```yaml
privileged: true
capabilities:
  add:
  - SYS_ADMIN
  - NET_ADMIN
runAsUser: 0
```

Remove the volumes section entirely:
```yaml
volumes:
- name: host-root
  hostPath:
    path: /
    type: Directory
```

And the corresponding volumeMounts.
</details>

<details>
<summary>Hint 4: Complete namespace labels example</summary>

```yaml
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: latest
```
</details>

<details>
<summary>Hint 5: Seccomp and capabilities configuration</summary>

For the seccomp profile (at both pod and container level):
```yaml
seccompProfile:
  type: RuntimeDefault
```

To drop all capabilities:
```yaml
capabilities:
  drop:
  - ALL
```

Use UID 1000 as a safe non-root user:
```yaml
runAsUser: 1000
runAsGroup: 1000
fsGroup: 1000
```
</details>

---

## Step 4: Deploy Your Secured Namespace and Pod

First, clean up the insecure deployment:

```bash
kubectl delete -f start/pod.yml
kubectl delete -f start/namespace.yml
```

Now apply your modified manifests with the Pod Security Standards enforcement:

```bash
kubectl apply -f start/namespace.yml
```

Try to apply the secured pod:

```bash
kubectl apply -f start/pod.yml
```

If the pod still violates the restricted profile, you'll see an error message explaining what needs to be fixed. Keep iterating until the pod is admitted.

Wait for the pod to be ready:

```bash
kubectl wait --for=condition=Ready pod/pss-demo -n pss-test --timeout=60s
```

---

## Step 5: Verify Security Controls

Now let's verify that our security controls are in place and that dangerous configurations are blocked.

### Test 1: Verify pod runs as non-root

```bash
kubectl exec -n pss-test pss-demo -- id
```

<details>
<summary>Expected output</summary>

```
uid=1000 gid=1000 groups=1000
```

**Success!** The container now runs as UID 1000, a non-privileged user with minimal permissions.
</details>

### Test 2: Verify privileged mode is disabled

```bash
kubectl get pod -n pss-test pss-demo -o jsonpath='{.spec.containers[0].securityContext.privileged}'
```

<details>
<summary>Expected output</summary>

```
(empty output or false)
```

**Success!** The container no longer runs in privileged mode, maintaining the security boundary between container and host.
</details>

### Test 3: Check that dangerous capabilities are dropped

```bash
kubectl get pod -n pss-test pss-demo -o jsonpath='{.spec.containers[0].securityContext.capabilities}'
```

<details>
<summary>Expected output</summary>

```
{"drop":["ALL"]}
```

**Success!** All capabilities are dropped, following the principle of least privilege.
</details>

### Test 4: Verify host namespaces are not accessible

```bash
kubectl get pod -n pss-test pss-demo -o jsonpath='{.spec.hostPID}{"\n"}{.spec.hostNetwork}{"\n"}{.spec.hostIPC}{"\n"}'
```

<details>
<summary>Expected output</summary>

```
(empty lines - all false or absent)
```

**Success!** The container is isolated from host namespaces and cannot see host processes or network interfaces.
</details>

### Test 5: Attempt to see host processes

```bash
kubectl exec -n pss-test pss-demo -- ps aux
```

<details>
<summary>Expected output</summary>

```
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
1000         1  0.0  0.0   2888  1024 ?        Ss   13:00   0:00 sh -c while true; do sleep 3600; done
1000         7  0.0  0.0   2888   512 ?        S    13:00   0:00 sleep 3600
1000        42  0.0  0.0   7644  1536 ?        Rs   13:05   0:00 ps aux
```

**Success!** The container can only see its own processes, not the host processes.
</details>

### Test 6: Verify host filesystem is not mounted

```bash
kubectl exec -n pss-test pss-demo -- ls -la /host 2>&1
```

<details>
<summary>Expected output</summary>

```
ls: cannot access '/host': No such file or directory
```

**Success!** The host filesystem is not mounted, preventing any access to host files.
</details>

### Test 7: Confirm privilege escalation is disabled

```bash
kubectl get pod -n pss-test pss-demo -o jsonpath='{.spec.containers[0].securityContext.allowPrivilegeEscalation}'
```

<details>
<summary>Expected output</summary>

```
false
```

**Success!** Processes inside the container cannot escalate privileges through SUID binaries or other mechanisms.
</details>

### Test 8: Verify seccomp profile is applied

```bash
kubectl get pod -n pss-test pss-demo -o jsonpath='{.spec.securityContext.seccompProfile.type}'
```

<details>
<summary>Expected output</summary>

```
RuntimeDefault
```

**Success!** The RuntimeDefault seccomp profile is applied, restricting available system calls.
</details>

### Test 9: Verify namespace enforces Pod Security Standards

```bash
kubectl get namespace pss-test -o jsonpath='{.metadata.labels}' | grep -o 'pod-security[^,}]*' | sort
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

**Success!** The namespace enforces the restricted Pod Security Standard at the admission control level.
</details>

### Test 10: Attempt to deploy a non-compliant pod

Create a test file to verify admission control:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: privileged-test
  namespace: pss-test
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

**Success!** The Kubernetes API server blocks non-compliant pods at admission time, preventing deployment of insecure configurations.
</details>

### Test 11: Verify legitimate functionality still works

```bash
kubectl exec -n pss-test pss-demo -- echo "Hello from secure container"
```

<details>
<summary>Expected output</summary>

```
Hello from secure container
```

**Success!** Despite the security restrictions, the container can still perform its intended legitimate functions.
</details>

---

## Step 6: Compare with Reference Solution

Compare your namespace configuration with the reference solution:

```bash
diff start/namespace.yml done/namespace.yml
```

Compare your pod configuration with the reference solution:

```bash
diff start/pod.yml done/pod.yml
```

View the complete reference namespace:

```bash
cat done/namespace.yml
```

View the complete reference pod:

```bash
cat done/pod.yml
```

---

## What We've Prevented

### Attack Vector 1: Container Escape via Privileged Mode
- **Before:** An attacker with code execution in the container could leverage privileged mode to escape to the host, gaining full control of the node
- **After:** Privileged mode is blocked by PSS enforcement, and the container runs with minimal capabilities

### Attack Vector 2: Host Filesystem Access
- **Before:** An attacker could read sensitive host files (SSH keys, certificates, kubeconfig) or modify system binaries to establish persistence
- **After:** HostPath volumes are prohibited by the restricted profile, isolating the container filesystem

### Attack Vector 3: Host Namespace Access
- **Before:** An attacker could enumerate all host processes, network connections, and shared memory, facilitating lateral movement and reconnaissance
- **After:** Host namespace sharing (PID, Network, IPC) is blocked, preventing visibility into host operations

### Attack Vector 4: Privilege Escalation via SUID Binaries
- **Before:** An attacker could exploit SUID binaries to escalate from a low-privileged process to root inside the container, then leverage other misconfigurations
- **After:** AllowPrivilegeEscalation is set to false, preventing processes from gaining additional privileges

### Attack Vector 5: Kernel Exploitation via Unrestricted System Calls
- **Before:** An attacker could attempt kernel exploits using any available system call, maximizing the attack surface
- **After:** The RuntimeDefault seccomp profile restricts available system calls to a safe subset, reducing the kernel attack surface

---

## Security Hardening Levels

| Level | Feature | Risk Mitigated |
|-------|---------|----------------|
| **Basic** | RunAsNonRoot enforcement | Prevents root user execution, limiting damage from compromised containers |
| **Basic** | Drop all capabilities | Removes Linux capabilities that enable privileged operations |
| **Intermediate** | Disable privilege escalation | Prevents processes from gaining more privileges than their parent |
| **Intermediate** | Seccomp profile (RuntimeDefault) | Restricts system calls available to the container, limiting kernel exposure |
| **Advanced** | Block host namespace sharing | Prevents access to host PID, Network, and IPC namespaces |
| **Advanced** | Prohibit hostPath volumes | Prevents mounting of host filesystem paths into containers |
| **Expert** | Namespace-level PSS enforcement | Provides cluster-wide admission control, preventing deployment of non-compliant pods |
| **Expert** | Multiple PSS modes (enforce/warn/audit) | Enables gradual rollout with visibility into violations before strict enforcement |

---

## Cleanup

Remove all resources created during this exercise:

```bash
kubectl delete -f start/pod.yml
kubectl delete -f start/namespace.yml
```

Verify cleanup:

```bash
kubectl get namespace pss-test 2>&1
```

You should see: `Error from server (NotFound): namespaces "pss-test" not found`

---

## Bonus: Comparing All Three Pod Security Levels

Let's see the difference between the three PSS levels: privileged, baseline, and restricted.

⚠️ **Warning:** This bonus section demonstrates dangerous configurations for educational purposes only. Never use these in production!

Create three namespaces with different PSS levels:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: pss-privileged
  labels:
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/warn: privileged
    pod-security.kubernetes.io/audit: privileged
---
apiVersion: v1
kind: Namespace
metadata:
  name: pss-baseline
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/warn: baseline
    pod-security.kubernetes.io/audit: baseline
---
apiVersion: v1
kind: Namespace
metadata:
  name: pss-restricted
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/audit: restricted
EOF
```

Try deploying a privileged pod to each namespace:

```bash
# This will succeed (no restrictions)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-privileged
  namespace: pss-privileged
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

# This will fail (baseline blocks privileged)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-baseline
  namespace: pss-baseline
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

# This will also fail (restricted blocks privileged and requires more)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-restricted
  namespace: pss-restricted
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

Now try a pod that meets baseline requirements but not restricted:

```bash
# This will succeed in baseline namespace
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-baseline-ok
  namespace: pss-baseline
spec:
  containers:
  - name: test
    image: nginx:1.27
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
      limits:
        memory: "128Mi"
        cpu: "200m"
EOF

# This will fail in restricted namespace (missing runAsNonRoot, seccomp, etc.)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-restricted-fail
  namespace: pss-restricted
spec:
  containers:
  - name: test
    image: nginx:1.27
    resources:
      requests:
        memory: "64Mi"
        cpu: "100m"
      limits:
        memory: "128Mi"
        cpu: "200m"
EOF
```

**Key Insight:** The `restricted` profile is significantly more stringent than `baseline`, requiring explicit security configurations rather than just blocking the most dangerous settings.

Clean up the bonus namespaces:

```bash
kubectl delete namespace pss-privileged pss-baseline pss-restricted
```

---

## Key Takeaways

- **Pod Security Standards provide three levels** — privileged (unrestricted), baseline (minimally restrictive), and restricted (heavily restricted following current best practices)
- **Pod Security Admission is namespace-scoped** — enforcement is applied at the namespace level using labels, enabling gradual rollout and per-team policies
- **The restricted profile is production-ready** — it enforces best practices like running as non-root, dropping capabilities, using seccomp profiles, and blocking host access
- **Multiple modes enable safe adoption** — using `enforce`, `warn`, and `audit` together allows teams to understand violations before blocking deployments
- **Admission control happens early** — PSS violations are caught at API admission time, before the pod is scheduled or run, preventing security incidents
- **Security doesn't mean non-functional** — properly configured restricted pods can perform all legitimate application functions while maintaining strong security boundaries
- **Defense in depth requires layered controls** — PSS complements (but doesn't replace) network policies, RBAC, and runtime security tools
- **Default deny is the safest approach** — enforcing `restricted` by default and carving out exceptions for specific workloads is safer than enforcing `privileged` everywhere

---

## Next Steps

1. **Audit your existing namespaces** — Check which namespaces lack PSS labels and assess the blast radius of non-compliant pods
2. **Enable audit and warn modes first** — Before enforcing, use audit and warn modes to understand which workloads would be blocked
3. **Create exemptions for legacy workloads** — Use namespace exclusions or Pod Security Admission configuration for workloads that genuinely need privileged access
4. **Explore OPA/Gatekeeper for custom policies** — PSS covers pod-level security; Gatekeeper can enforce organization-specific requirements
5. **Implement runtime security monitoring** — Use tools like Falco to detect anomalous behavior even in compliant pods
6. **Review the Network Policies exercise** — Combine PSS with network segmentation for comprehensive defense in depth

---

## Further Reading

- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)
- [Configure Pod Security Standards for a Namespace](https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/)
- [Security Context Configuration](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)

