# Kubernetes Advanced Security Exercises

A collection of hands-on exercises for learning Kubernetes security best practices through an "exploit-then-harden" approach. Each exercise guides you through deploying insecure configurations, testing attack vectors, and applying security controls.

## Exercises

### 1. [Pod Security Context](./pod-security-context/)
Learn how to configure security contexts at the pod and container level to implement defense-in-depth.

**Topics covered:**
- Running containers as non-root users
- Dropping Linux capabilities
- Setting read-only root filesystems
- Disabling privilege escalation
- Applying seccomp profiles

**Difficulty:** Beginner to Intermediate

---

### 2. [Pod Security Standards](./pod-security-standards/)
Understand how Pod Security Admission enforces security policies at the namespace level.

**Topics covered:**
- Pod Security Standards (privileged, baseline, restricted)
- Pod Security Admission labels and modes
- Namespace-level security enforcement
- Complying with the restricted profile
- Gradual rollout strategies with enforce/warn/audit modes

**Difficulty:** Intermediate

---

## Prerequisites

- A Kubernetes cluster (1.28 or later recommended)
- `kubectl` configured to access your cluster
- Basic understanding of Kubernetes pods, namespaces, and YAML manifests
- Familiarity with Linux security concepts (users, capabilities, namespaces)

## How to Use These Exercises

Each exercise follows the same pattern:

1. **Deploy the insecure configuration** — Start with manifests in the `start/` directory that demonstrate security weaknesses
2. **Test attack vectors** — Run commands that exploit the security gaps
3. **Apply security controls** — Modify the manifests to implement best practices
4. **Verify protections** — Confirm that previous attacks are now blocked
5. **Compare with reference solution** — Check your work against the `done/` directory

## Learning Philosophy

These exercises use an **exploit-then-harden** approach because:

- **Understanding why** matters more than memorizing configurations
- **Seeing attacks succeed** makes the risks concrete and memorable
- **Testing protections** builds confidence that security controls actually work
- **Hands-on practice** beats passive reading for retention and skill development

## Contributing

Contributions are welcome! If you'd like to add a new exercise or improve an existing one, please refer to the [Exercise Generator Instructions](./EXERCISE_GENERATOR_INSTRUCTIONS.md) for the required format and structure.

## License

This project is provided for educational purposes.
