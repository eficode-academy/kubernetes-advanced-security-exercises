# Custom Instructions: Kubernetes Security Exercise Generator

Use these instructions to generate hands-on Kubernetes security exercises that follow a consistent, proven pedagogical structure. The exercises target intermediate-to-advanced Kubernetes practitioners and follow an "exploit-then-harden" pattern.

---

## 1. Overall Repository Structure

Each exercise lives in its own top-level directory within the repository. The directory name should be a kebab-case slug of the topic (e.g., `pod-security-context`, `network-policies`, `rbac`).

```
kubernetes-advanced-security-exercises/
├── README.md                    # Repo-level overview listing all exercises
├── <exercise-slug>/
│   ├── README.md                # Full exercise instructions (the main deliverable)
│   ├── start/                   # Starting manifests — insecure/minimal baseline
│   │   └── <resource>.yml       # One or more YAML manifests
│   └── done/                    # Reference solution — fully hardened manifests
│       └── <resource>.yml       # Matching filenames to start/
```

### Rules for `start/` and `done/`

- **`start/`** contains the minimum viable, *working* Kubernetes manifests with **no security hardening**. They must deploy successfully and expose the security weaknesses the exercise teaches about.
- **`done/`** contains the same manifests with all security controls applied. The diff between `start/` and `done/` **is** the exercise solution.
- File names must match between `start/` and `done/` so `diff start/ done/` produces a clean comparison.
- All manifests use `.yml` extension (not `.yaml`) for consistency.
- All manifests must include `resources.requests` and `resources.limits` for containers — this models production best practice even when not the focus of the exercise.

---

## 2. README.md Structure (Exercise Instructions)

Every exercise README follows this exact structure. Do not skip or reorder sections.

### 2.1 Title

```markdown
# <Topic Name>
```

A short, descriptive title in Title Case (e.g., "Network Policies", "RBAC Authorization", "Pod Security Standards").

### 2.2 Learning Objectives

```markdown
## Learning Objectives

In this exercise, you will:
- <verb phrase describing what the student will do>
- <verb phrase about understanding the risk>
- <verb phrase about applying the fix>
- <verb phrase about verifying the fix>
```

- Use 3–5 bullet points.
- Start each with a strong verb: Deploy, Understand, Apply, Verify, Configure, Test, Create, Observe.
- Follow Bloom's taxonomy: move from knowledge → application → analysis.

### 2.3 Exercise Pattern

```markdown
## Exercise Pattern

1. **Deploy the insecure configuration** → See it work
2. **Test dangerous operations** → See them succeed (bad!)
3. **Apply security best practices** → Modify the manifests
4. **Test the same operations** → See them fail (good!)
```

This section is **identical in every exercise**. It establishes the exploit-then-harden mental model.

### 2.4 Step 1: Deploy the Insecure/Baseline Configuration

```markdown
## Step 1: Deploy the <Insecure|Baseline> <Resource>
```

- Provide the exact `kubectl apply -f start/` command.
- Provide a `kubectl wait` or equivalent readiness check command.
- If additional setup is needed (namespaces, service accounts), include those commands here with explanation.
- Use horizontal rules (`---`) between steps.

### 2.5 Step 2: Test Security Issues (The Exploit Phase)

```markdown
## Step 2: Test Security Issues (The Exploit Phase)
```

This is the core teaching section. It contains **numbered tests** that demonstrate specific security weaknesses.

#### Test Format

Each test follows this template:

```markdown
### Test N: <Short description of what is being tested>

\```bash
<kubectl command to run>
\```

<details>
<summary>Expected output</summary>

\```
<exact expected output or representative output>
\```

**Problem:** <One-sentence explanation of why this is dangerous, written from an attacker's perspective.>
</details>
```

#### Test Design Rules

1. **Number tests sequentially** starting from 1.
2. **Each test is a single concept** — one security weakness per test.
3. **Commands must be copy-pasteable** — no placeholders unless absolutely necessary.
4. **Use `kubectl exec`** for in-pod tests, `kubectl auth can-i` for RBAC tests, `kubectl get/describe` for policy tests, and direct `curl`/`wget` for network tests.
5. **Expected output is inside a `<details>` collapse** so students can try first, then check.
6. **Every test ends with a "Problem:" statement** explaining the risk in attacker-centric language.
7. **Order tests from least to most dangerous** to build tension.
8. Include **6–10 tests** per exercise to thoroughly cover the attack surface.
9. Where the test reveals information (rather than performing an action), use "What you'll see" instead of "Expected output" as the summary text.

### 2.6 Step 3: Apply Security Controls

```markdown
## Step 3: <Apply Security Context | Create Network Policies | Configure RBAC | ...>
```

This is the **student's task**. Structure it as:

1. **Brief introduction** — one paragraph explaining what they need to do.
2. **"Your Task" subsection** — a numbered list of specific changes to make.
3. **Progressive hints** — use nested `<details>` blocks, from vague to specific:
   - Hint 1: *Where* to make changes (which file, which section).
   - Hint 2: *What* fields/resources to use (key names, resource types).
   - Hint 3: *Exact YAML snippets* for the hardest parts only.

#### Hint Format

```markdown
<details>
<summary>Hint: <Short description></summary>

<content — can include YAML snippets, explanations, links>
</details>
```

- Provide **3–5 hints**, ordered from least to most revealing.
- The final hint should **not** be the complete solution — that's what `done/` is for.
- For exercises requiring creation of new resources (e.g., NetworkPolicy, Role, RoleBinding), provide the skeleton structure in a hint but leave key fields for the student to fill in.

### 2.7 Step 4: Deploy the Secured Configuration

```markdown
## Step 4: Deploy Your Secured <Resource>
```

- Delete the old resources first: `kubectl delete -f start/`
- Apply the modified manifests: `kubectl apply -f start/`
- Wait for readiness.
- If the exercise involves new files (e.g., NetworkPolicy), mention applying those too.

### 2.8 Step 5: Verify Security Controls

```markdown
## Step 5: Verify Security Controls
```

**Mirror Step 2 exactly.** Re-run the same tests (or equivalent) and show that:
- Previously succeeding attacks now **fail**.
- Legitimate operations still **work**.

Use the same numbered test format. Each test should have:
- The command to run.
- Expected output in a `<details>` collapse.
- A **"Success!"** statement explaining what security control is now active.

**Important:** Include at least one test that verifies legitimate functionality still works (e.g., "writing to /tmp still works", "allowed pod-to-pod traffic still works", "authorized user can still list pods"). This prevents students from thinking security = breaking everything.

### 2.9 Step 6: Compare with Reference Solution

```markdown
## Step 6: Compare with Reference Solution
```

Always include:

```bash
diff start/<file>.yml done/<file>.yml
```

And:

```bash
cat done/<file>.yml
```

If the exercise involves multiple new files, list each diff/cat command.

### 2.10 "What We've Prevented" Section

```markdown
## What We've Prevented
```

List 3–5 attack vectors using this format:

```markdown
### Attack Vector N: <Attack Name>
- **Before:** <What an attacker could do>
- **After:** <Why they can't anymore>
```

Map directly to MITRE ATT&CK for Containers tactics where possible (Initial Access, Execution, Persistence, Privilege Escalation, Defense Evasion, Credential Access, Discovery, Lateral Movement, Impact).

### 2.11 Security Hardening Levels Table

```markdown
## Security Hardening Levels
```

A markdown table mapping each control to a difficulty level and the risk it mitigates:

```markdown
| Level | Feature | Risk Mitigated |
|-------|---------|----------------|
| **Basic** | ... | ... |
| **Intermediate** | ... | ... |
| **Advanced** | ... | ... |
| **Expert** | ... | ... |
```

Use levels: Basic, Intermediate, Advanced, Expert. Each exercise should span at least 3 levels.

### 2.12 Cleanup

```markdown
## Cleanup
```

Provide the exact commands to remove all resources created during the exercise, including any namespaces, CRDs, or cluster-scoped resources.

### 2.13 Bonus Section (Optional)

```markdown
## Bonus: <Catchy Title>
```

An optional "nuclear option" or extreme scenario that demonstrates the worst-case version of the vulnerability. This should:
- Be clearly marked as dangerous / "never do this in production".
- Provide self-contained YAML (inline, not in `start/`).
- Include deploy, test, and cleanup commands.
- Reinforce the lesson by showing the extreme end of the spectrum.

### 2.14 Key Takeaways

```markdown
## Key Takeaways
```

- 5–8 bullet points.
- Each starts with a **bold phrase** summarizing the takeaway.
- Written as memorable principles, not just facts.
- Include at least one takeaway about defense-in-depth and least privilege.

### 2.15 Next Steps

```markdown
## Next Steps
```

- 3–6 numbered items pointing to related topics, tools, or exercises.
- Progress from immediate next actions to longer-term learning goals.

### 2.16 Further Reading

```markdown
## Further Reading
```

- 2–4 links to official Kubernetes documentation.
- Use the `[Title](URL)` format.
- Prefer `kubernetes.io/docs/` links.

---

## 3. YAML Manifest Conventions

### General

- Use `apiVersion`, `kind`, `metadata`, `spec` ordering.
- Always include `metadata.labels` with at least `app: <name>`.
- Use meaningful resource names that relate to the exercise (e.g., `security-demo`, `network-demo`, `rbac-demo`).
- Keep the container image simple and well-known: `ubuntu:22.04`, `nginx:1.27`, `busybox:1.36`, `curlimages/curl:latest`.
- Use `while true; do sleep 3600; done` as the keep-alive pattern for long-running demo pods.
- Always set resource requests and limits.

### `start/` Manifests

- Minimal — only what's needed to deploy and demonstrate the vulnerability.
- **No** security context, network policies, RBAC restrictions, or PSS labels.
- Include comments only if they explain what the pod does, not security guidance.

### `done/` Manifests

- Fully hardened version of the same resources.
- Include **inline comments** explaining each security control:
  ```yaml
  securityContext:
    # Ensure container doesn't run as root
    runAsNonRoot: true
  ```
- Group security-related fields together with a section comment:
  ```yaml
  # Pod-level security context
  securityContext:
    ...

  # Container-level security context
  securityContext:
    ...
  ```
- If new resources are needed (NetworkPolicy, Role, RoleBinding), add them as separate files in `done/` and provide corresponding empty or absent files in `start/` where appropriate.

---

## 4. Writing Style & Tone

- **Direct and concise** — no filler, no "In this section, we will..."
- **Second person** — "you", "your" — addressing the student directly.
- **Attacker's perspective** in the exploit phase: "An attacker could...", "This allows..."
- **Defender's perspective** in the hardening phase: "This prevents...", "Now the container cannot..."
- **Bold key terms** on first use within a section.
- Use **imperative mood** for instructions: "Deploy the pod", "Edit the manifest", "Run the command".
- Avoid jargon without explanation — if a term like "seccomp" or "RBAC" is used, briefly explain it inline or in the first mention.

---

## 5. Topic-Specific Guidance

Use the following guidance when generating exercises for specific topics. Each section describes what to put in `start/`, `done/`, and the key tests.

### 5.1 Pod Security Standards (PSS) / Pod Security Admission (PSA)

**`start/` contents:**
- A namespace without any PSS labels.
- A pod manifest that violates the "restricted" profile (runs as root, has capabilities, etc.).

**`done/` contents:**
- The namespace with PSS labels (`pod-security.kubernetes.io/enforce: restricted`, etc.).
- The pod manifest modified to comply with the restricted profile.

**Key tests (exploit phase):**
- Deploy a privileged pod — succeeds (no admission control).
- Deploy a pod with `hostPID: true` — succeeds.
- Deploy a pod with `hostNetwork: true` — succeeds.
- Deploy a pod running as root — succeeds.

**Key tests (verify phase):**
- Deploy a privileged pod — rejected by admission controller with clear error.
- Deploy a pod with `hostPID: true` — rejected.
- Deploy a compliant pod — succeeds.
- Show audit/warning labels in action (use `warn` and `audit` modes alongside `enforce`).

**Bonus:** Show all three PSS levels (privileged, baseline, restricted) side by side.

### 5.2 Network Policies

**`start/` contents:**
- Two or three pods in the same namespace (e.g., `frontend`, `backend`, `database`) with a Service for each.
- No NetworkPolicy resources.

**`done/` contents:**
- Same pods and services.
- NetworkPolicy resources implementing:
  - Default deny all ingress.
  - Allow frontend → backend on specific port.
  - Allow backend → database on specific port.
  - Deny frontend → database (direct access).

**Key tests (exploit phase):**
- `kubectl exec frontend -- curl backend:8080` — succeeds.
- `kubectl exec frontend -- curl database:5432` — succeeds (bad! frontend shouldn't talk to DB).
- `kubectl exec backend -- curl frontend:80` — succeeds (bad! backend shouldn't initiate to frontend).
- `kubectl exec database -- curl backend:8080` — succeeds (bad! database shouldn't call backend).
- External/cross-namespace access test if applicable.

**Key tests (verify phase):**
- `kubectl exec frontend -- curl backend:8080` — succeeds (allowed).
- `kubectl exec frontend -- curl database:5432` — times out/fails (blocked).
- `kubectl exec backend -- curl database:5432` — succeeds (allowed).
- `kubectl exec database -- curl backend:8080` — times out/fails (blocked).

**Bonus:** Demonstrate egress policies blocking pods from reaching the internet.

### 5.3 RBAC (Role-Based Access Control)

**`start/` contents:**
- A ServiceAccount with a ClusterRoleBinding to `cluster-admin` (overly permissive).
- A pod using that ServiceAccount.

**`done/` contents:**
- A ServiceAccount with a namespaced Role and RoleBinding granting only specific, least-privilege permissions.
- The same pod using the tightened ServiceAccount.
- `automountServiceAccountToken: false` where possible.

**Key tests (exploit phase):**
- `kubectl auth can-i --as=system:serviceaccount:<ns>:<sa> get secrets` — yes (bad!).
- `kubectl auth can-i --as=system:serviceaccount:<ns>:<sa> create pods` — yes (bad!).
- `kubectl auth can-i --as=system:serviceaccount:<ns>:<sa> delete deployments` — yes (bad!).
- From inside the pod, use `curl` to hit the Kubernetes API and list secrets.

**Key tests (verify phase):**
- `kubectl auth can-i --as=system:serviceaccount:<ns>:<sa> get secrets` — no.
- `kubectl auth can-i --as=system:serviceaccount:<ns>:<sa> get pods` — yes (allowed).
- `kubectl auth can-i --as=system:serviceaccount:<ns>:<sa> delete deployments` — no.
- From inside the pod, API calls for unauthorized resources return 403 Forbidden.

**Bonus:** Demonstrate token projection and audience-scoped tokens.

### 5.4 Additional Topics (Follow Same Pattern)

For any new topic, apply the same framework:

1. Identify the **default insecure behavior** in Kubernetes.
2. Design `start/` manifests that **expose** that behavior.
3. Design `done/` manifests that **fix** it.
4. Write **exploit tests** proving the weakness exists.
5. Write **verify tests** proving the fix works.
6. Add progressive hints guiding students from the problem to the solution.

Applicable additional topics:
- **Secrets Management** — Secrets as env vars vs. mounted volumes, encryption at rest.
- **Image Security** — Image pull policies, image scanning, private registries, digest pinning.
- **Audit Logging** — Audit policy configuration, log analysis.
- **Service Mesh Security** — mTLS with Istio/Linkerd.
- **OPA/Gatekeeper Policies** — Custom admission control.
- **Supply Chain Security** — Cosign, SBOM, admission controllers for signed images.
- **Runtime Security** — Falco rules, detecting anomalous behavior.

---

## 6. Quality Checklist

Before finalizing any exercise, verify:

- [ ] `start/` manifests deploy successfully with no errors on a standard Kubernetes cluster (1.28+).
- [ ] `done/` manifests deploy successfully with no errors.
- [ ] All `kubectl` commands in the README are copy-pasteable without modification.
- [ ] All expected outputs are realistic and match what the commands produce.
- [ ] Every exploit test in Step 2 has a corresponding verify test in Step 5.
- [ ] At least one verify test confirms legitimate functionality still works.
- [ ] Progressive hints exist (3–5 per exercise) going from vague to specific.
- [ ] `diff start/ done/` produces a meaningful and readable diff.
- [ ] Cleanup commands remove **all** resources created during the exercise.
- [ ] No hardcoded cluster-specific values (node names, IPs, etc.).
- [ ] README renders correctly in GitHub-flavored Markdown.
- [ ] YAML files pass `kubectl apply --dry-run=client -f <file>` validation.
- [ ] The exercise can be completed in 20–40 minutes by an intermediate practitioner.
- [ ] Key Takeaways section contains 5–8 memorable principles.
- [ ] Further Reading links point to current, valid Kubernetes documentation URLs.

---

## 7. Example Exercise Generation Prompt

When using these instructions with an AI assistant, use a prompt like:

```
Using the exercise generator instructions in EXERCISE_GENERATOR_INSTRUCTIONS.md, generate a complete exercise for the topic: "<TOPIC NAME>".

Generate:
1. The full README.md for the exercise
2. All files for the start/ directory
3. All files for the done/ directory

Ensure the exercise follows the exploit-then-harden pattern and includes all required sections.
```

---

## 8. Naming Conventions Reference

| Topic | Directory Name | Pod/Resource Name | Namespace (if needed) |
|-------|---------------|-------------------|----------------------|
| Pod Security Context | `pod-security-context` | `security-demo` | default |
| Pod Security Standards | `pod-security-standards` | `pss-demo` | `pss-test` |
| Network Policies | `network-policies` | `frontend`, `backend`, `database` | `netpol-demo` |
| RBAC | `rbac` | `rbac-demo` | `rbac-test` |
| Secrets Management | `secrets-management` | `secrets-demo` | `secrets-test` |
| Image Security | `image-security` | `image-demo` | default |
| Audit Logging | `audit-logging` | `audit-demo` | default |
| Runtime Security | `runtime-security` | `runtime-demo` | default |

