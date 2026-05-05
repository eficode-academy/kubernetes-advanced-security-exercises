# kubernetes-advanced-security-exercises

A selection of exercises for advanced Kubernetes security topics.

The exercises are ordered to build on each other — each one introduces a new layer of the Kubernetes security model.

> :exclamation: The exercises expect that you have access to a Kubernetes cluster and a personal namespace.
> Please check with your instructor if you have not been assigned one.

## Exercises in suggested order

- [Pod Security Context](pod-security-context/pod-security-context.md) — Harden pod specs with security context
- [Pod Security Standards](pod-security-standards/pod-security-standards.md) — Enforce standards cluster-wide with Pod Security Admission
- [Network Policies](network-policies/network-policies.md) — Restrict pod-to-pod and pod-to-external traffic using Kubernetes network policies
- [RBAC & Service Accounts](rbac-service-account/rbac-service-account.md) — Control access to the Kubernetes API with roles, role bindings, and service accounts

## Prerequisites

You will need:
- A Kubernetes cluster (provided by your instructor, or see options below)
- `kubectl` configured to talk to the cluster
- A personal namespace assigned to you

### Getting a cluster

[Amazon][eks], [Google][gke], [Microsoft][aks] and [Oracle][oke] provide various degrees of free managed clusters.

Alternatively, you can set up a local cluster with [Docker Desktop][docker-desktop] or [Kind][kind].

### kubectl autocompletion

On Linux/macOS with bash:

```shell
echo "source <(kubectl completion bash)" >> ~/.bashrc
. ~/.bashrc
```

On macOS with zsh:

```shell
echo "source <(kubectl completion zsh)" >> ~/.zshrc
. ~/.zshrc
```

See: [Kubernetes.io - Enabling shell autocompletion][autocompletion] for more info.

## Useful commands

```shell
kubectl api-resources         # List resource types
kubectl explain <resource>    # Show information about a resource

# List resources in cluster
kubectl get <resource>                    # In current namespace
kubectl get <resource> -n <namespace>     # In specific namespace
kubectl get <resource> --all-namespaces   # In all namespaces
kubectl get <resource> -o wide            # Add extended information
kubectl get <resource> -o yaml            # Output in YAML format
kubectl get <resource> -o json            # Output in JSON format

# Example
kubectl get pods [-n abc|--all-namespaces] [-o wide|yaml|json]

# Useful for security exercises
kubectl auth can-i <verb> <resource>                    # Check your own permissions
kubectl auth can-i <verb> <resource> --as <user>        # Check another user's permissions
kubectl get pod <name> -o jsonpath='{.spec.securityContext}'
```

See [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/) for a more extended overview.

[eks]: https://aws.amazon.com/ecs/pricing/
[gke]: https://cloud.google.com/kubernetes-engine/pricing#cluster_management_fee_and_free_tier
[aks]: https://azure.microsoft.com/en-us/pricing/free-services/
[oke]: https://www.oracle.com/cloud/free/#free-cloud-trial
[docker-desktop]: https://docs.docker.com/desktop/
[kind]: https://kind.sigs.k8s.io/
[autocompletion]: https://kubernetes.io/docs/tasks/tools/install-kubectl/#enabling-shell-autocompletion
