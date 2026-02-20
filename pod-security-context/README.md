# Pod Security Context

## Learning Objectives

In this exercise, you will:
- Deploy a pod with no security restrictions and see what it can do
- Understand the security risks of running containers with excessive privileges
- Apply security context to harden the pod
- Verify that previous dangerous operations are now blocked

## Exercise Pattern

1. **Deploy the insecure configuration** → See it work
2. **Test dangerous operations** → See them succeed (bad!)
3. **Apply security best practices** → Modify the pod manifest
4. **Test the same operations** → See them fail (good!)

---

## Step 1: Deploy the Insecure Pod

Deploy the pod from the `start/` folder:

```bash
kubectl apply -f start/
```

Wait for the pod to be ready:

```bash
kubectl wait --for=condition=ready pod/security-demo --timeout=60s
```

---

## Step 2: Test Security Issues (The Exploit Phase)

Now let's see what this pod can do. These tests simulate real attacker behavior.

### Test 1: Check what user the container runs as

```bash
kubectl exec security-demo -- id
```

<details>
<summary>Expected output</summary>

```
uid=0(root) gid=0(root) groups=0(root)
```

**Problem:** The container is running as root (UID 0)!
</details>

### Test 2: Can we write to the root filesystem?

```bash
kubectl exec security-demo -- touch /malware.sh
kubectl exec security-demo -- ls -la /malware.sh
```

<details>
<summary>Expected output</summary>

```
-rw-r--r-- 1 root root 0 Jan 5 12:00 /malware.sh
```

**Problem:** We can write arbitrary files to the root filesystem. An attacker could install malware or backdoors!
</details>

### Test 3: Can we modify system binaries?

```bash
kubectl exec security-demo -- sh -c 'echo "malicious code" >> /bin/bash'
```

<details>
<summary>Expected output</summary>

```
(command succeeds silently)
```

**Problem:** We can modify system binaries! An attacker could inject malicious code.
</details>

### Test 4: Information Leakage - Kernel Version

```bash
kubectl exec security-demo -- cat /proc/version
```

<details>
<summary>What you'll see</summary>

You'll see the host's kernel version. An attacker can use this to identify known kernel vulnerabilities.

**Problem:** Container has visibility into host kernel information.
</details>

### Test 5: Information Leakage - CPU Info

```bash
kubectl exec security-demo -- cat /proc/cpuinfo
```

<details>
<summary>What you'll see</summary>

You'll see detailed CPU information from the host node, including model, number of cores, and flags.

**Problem:** Attackers can fingerprint the infrastructure and look for CPU-specific exploits.
</details>

### Test 6: Check Linux Capabilities

```bash
kubectl exec security-demo -- sh -c 'cat /proc/1/status | grep Cap'
```

<details>
<summary>Expected output</summary>

```
CapInh: 0000000000000000
CapPrm: 00000000a80425fb
CapEff: 00000000a80425fb
CapBnd: 00000000a80425fb
CapAmb: 0000000000000000
```

**What this means:** Even without being privileged, the container has capabilities like CHOWN, KILL, NET_BIND_SERVICE, etc. These can be exploited.
</details>

### Test 7: Access to Service Account Token

```bash
kubectl exec security-demo -- cat /var/run/secrets/kubernetes.io/serviceaccount/token
```

<details>
<summary>Expected output</summary>

You'll see a JWT token.

**Problem:** An attacker could steal this token to communicate with the Kubernetes API server and potentially escalate privileges.
</details>

### Test 8: Can we see processes on the host? (Most dangerous!)

```bash
kubectl exec security-demo -- ps aux
```

<details>
<summary>Expected output</summary>

You'll only see the container's bash process (PID 1) and ps itself.

```
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.0   4624  3712 ?        Ss   12:00   0:00 /bin/bash -c ...
```

**Current state:** Container is isolated in its own PID namespace (good!), but it's still running as root.
</details>

---

## Step 3: Apply Security Context

Now it's your turn! Modify the pod manifest to add proper security context.

### Your Task

Edit `start/pod.yaml` and add a `securityContext` section. You need to:

1. **Run as a non-root user** (use UID 10000)
2. **Make the root filesystem read-only**
3. **Prevent privilege escalation**
4. **Drop all Linux capabilities**
5. **Add a seccomp profile** to restrict system calls
6. **Add a writable volume** for `/tmp` (apps need somewhere to write!)

<details>
<summary>Hint: Where to add securityContext</summary>

You can add security context at two levels:
- **Pod level** under `spec.securityContext`
- **Container level** under `spec.containers[].securityContext`

```yaml
spec:
  securityContext:
    # Pod-level settings here
  containers:
  - name: app
    securityContext:
      # Container-level settings here
```
</details>

<details>
<summary>Hint: Key security settings</summary>

Here are the key fields you need:

**Pod-level:**
```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10000
    seccompProfile:
      type: RuntimeDefault
```

**Container-level:**
```yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
```
</details>

<details>
<summary>Hint: Making /tmp writable</summary>

Add an emptyDir volume and mount it to `/tmp`:

```yaml
volumeMounts:
- name: tmp
  mountPath: /tmp

volumes:
- name: tmp
  emptyDir: {}
```
</details>

---

## Step 4: Deploy Your Secured Pod

First, delete the insecure pod:

```bash
kubectl delete -f start/
```

Now deploy with your modifications:

```bash
kubectl apply -f start/pod.yaml
```

Wait for it to be ready:

```bash
kubectl wait --for=condition=ready pod/security-demo --timeout=60s
```

---

## Step 5: Verify Security Controls

Run the same tests again. This time they should fail!

### Test 1: Check the user (should be non-root now)

```bash
kubectl exec security-demo -- id
```

<details>
<summary>Expected output</summary>

```
uid=10000 gid=0(root) groups=0(root)
```

**Success!** Now running as non-root user (UID 10000)
</details>

### Test 2: Try writing to root filesystem (should fail)

```bash
kubectl exec security-demo -- touch /malware.sh
```

<details>
<summary>Expected output</summary>

```
touch: /malware.sh: Read-only file system
command terminated with exit code 1
```

**Success!** The filesystem is read-only. Attackers can't persist malware.
</details>

### Test 3: Try writing to /tmp (should work)

```bash
kubectl exec security-demo -- touch /tmp/test-file
kubectl exec security-demo -- ls -la /tmp/test-file
```

<details>
<summary>Expected output</summary>

```
-rw-r--r-- 1 10000 root 0 Jan 5 12:00 /tmp/test-file
```

**Success!** Applications can still write to designated areas.
</details>

### Test 4: Try to escalate privileges (should fail)

```bash
kubectl exec security-demo -- su -
```

<details>
<summary>Expected output</summary>

```
su: must be suid to work properly
command terminated with exit code 1
```

**Success!** Cannot escalate to root.
</details>

### Test 5: Verify capabilities are dropped

```bash
kubectl exec security-demo -- sh -c 'cat /proc/1/status | grep Cap'
```

<details>
<summary>Expected output</summary>

```
CapInh: 0000000000000000
CapPrm: 0000000000000000
CapEff: 0000000000000000
CapBnd: 0000000000000000
CapAmb: 0000000000000000
```

**Success!** All capability masks are now 0 - no Linux capabilities!
</details>

### Test 6: Verify seccomp profile is active

```bash
kubectl exec security-demo -- sh -c 'cat /proc/1/status | grep Seccomp'
```

<details>
<summary>Expected output</summary>

```
Seccomp: 2
Seccomp_filters: 1
```

**Success!** Seccomp is enabled (2 = filtering mode). This restricts which system calls the process can make to the kernel.
</details>

### Test 7: Information still visible (Note the limitation)

```bash
kubectl exec security-demo -- cat /proc/version
```

<details>
<summary>What you'll see</summary>

You can still see kernel information. SecurityContext doesn't hide `/proc` by default.

**Note:** For production, consider using AppArmor/SELinux profiles to mask sensitive paths, or implement Pod Security Standards with stricter policies.
</details>

---

## Step 6: Compare with Reference Solution

Check your work against the reference solution:

```bash
diff start/pod.yaml done/pod.yaml
```

Or view the complete solution:

```bash
cat done/pod.yaml
```

---

## What We've Prevented

### Attack Vector 1: Container Escape
- **Before:** Running as root with capabilities makes container escape easier
- **After:** Non-root user, no capabilities, can't escalate privileges

### Attack Vector 2: Filesystem Manipulation
- **Before:** Attacker can install malware, modify binaries, persist backdoors
- **After:** Read-only filesystem prevents any persistence

### Attack Vector 3: Lateral Movement
- **Before:** With root privileges, easier to access other containers/services
- **After:** Limited privileges reduce blast radius if compromised

### Attack Vector 4: Kernel Exploits
- **Before:** No syscall filtering - attacker can try any kernel exploit
- **After:** Seccomp profile blocks dangerous system calls

---

## Security Hardening Levels

Here's a comparison of different security hardening levels:

| Level | Feature | Risk Mitigated |
|-------|---------|----------------|
| **Basic** | `runAsNonRoot` | Prevents simple host file modification |
| **Intermediate** | `readOnlyRootFilesystem` | Prevents malware persistence and "configuration drift" |
| **Advanced** | `allowPrivilegeEscalation: false` | Blocks setuid binaries (like `sudo`) from working |
| **Expert** | `seccompProfile` | Limits the kernel attack surface (syscalls) |
| **Expert** | Drop all `capabilities` | Removes dangerous Linux kernel features |

---

## Cleanup

```bash
kubectl delete -f start/
```

---

## Bonus: The Nuclear Option - Host Namespaces

Want to see what happens when we give a pod FULL access to the host? This is what you should NEVER do in production!

Create a file called `dangerous-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: dangerous-pod
spec:
  hostPID: true      # Share host's process namespace!
  hostNetwork: true  # Share host's network namespace!
  containers:
  - name: app
    image: ubuntu:22.04
    command: ["/bin/bash", "-c", "while true; do sleep 3600; done"]
```

Deploy it:

```bash
kubectl apply -f dangerous-pod.yaml
kubectl wait --for=condition=ready pod/dangerous-pod --timeout=60s
```

Now try this:

```bash
kubectl exec dangerous-pod -- ps aux
```

**Result:** You can see ALL processes on the host node - not just your container! This includes system daemons, other containers, everything.

```bash
kubectl exec dangerous-pod -- ss -tulpn
```

**Result:** You can see all network connections on the host!

Cleanup:

```bash
kubectl delete pod dangerous-pod
```

**Lesson:** `hostPID` and `hostNetwork` give the container visibility into the entire node. This is sometimes needed for system-level tools (like monitoring agents), but should be avoided for application workloads.

---

## Key Takeaways

- **Containers run as root by default** - you must explicitly configure otherwise
- **Read-only filesystem** prevents malware persistence
- **Dropping capabilities** removes dangerous kernel features
- **Seccomp profiles** limit syscall attack surface
- **Defense in depth** - multiple controls provide better protection
- **Least privilege** - only grant minimum permissions needed
- **Host namespaces** should almost never be used for application pods

---

## Next Steps

1. Try applying these principles to a real application
2. Learn about Pod Security Standards (PSS) and Pod Security Admission (PSA)
3. Explore runtime security tools like Falco
4. Learn about AppArmor/SELinux profiles for masking sensitive paths
5. Investigate custom seccomp profiles for specific applications

## Further Reading

- [Kubernetes Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
