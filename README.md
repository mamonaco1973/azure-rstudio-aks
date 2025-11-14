# Azure RStudio Cluster on AKS with Active Directory and Azure Files (NFS) Integration

This project builds on both the **Azure Mini Active Directory** and **RStudio on Azure** lab components to deliver a **cloud-native, domain-joined RStudio Server environment** running on **Azure Kubernetes Service (AKS)**.

It uses **Terraform**, **Docker**, **Helm**, and **Kubernetes manifests** to create a fully automated analytics platform that integrates with:

- **Active Directory authentication** (via a Samba-based Mini-AD Domain Controller)  
- **Azure Files NFS shares** for persistent, shared storage  
- **Azure Workload Identity + Key Vault** for secure, secretless pod-level authentication  
- **Azure Container Registry (ACR)** for hosting the custom RStudio Server image  

Unlike VM-based scaling groups, this solution deploys **containerized RStudio Server pods** on AKS that join the domain at runtime and mount **NFS volumes** for user home directories, project data, and shared R library storage.

Key capabilities demonstrated:

1. **AKS-Hosted RStudio Server** – RStudio Server (Open Source Edition) runs as containers on Azure Kubernetes Service for elasticity, self-healing, and cost-efficient scaling.  
2. **Active Directory Authentication** – Pods authenticate against a Samba-based Active Directory domain, providing centralized and consistent user identity management.  
3. **Azure Files NFS Persistent Storage** – User home folders and shared R package libraries live on Azure Files (Premium, NFS v4), ensuring cross-pod consistency and reproducible environments.  
4. **NGINX Ingress with Public IP** – Provides external HTTPS access, session affinity, customizable routing, and native Azure Load Balancer integration.  
5. **End-to-End Infrastructure as Code** – Terraform builds the AD, networking, Key Vault, NFS storage, ACR, AKS cluster, workload identities, and ingress; Docker builds the RStudio image; Kubernetes + Helm deploy the full runtime stack.

Together, these components form a scalable, domain-aware analytics platform where RStudio users share packages, data, and authentication seamlessly across a fully managed Azure Kubernetes environment.

## Prerequisites

* [An Azure Account](https://portal.azure.com/)
* [Install AZ CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) 
* [Install Latest Terraform](https://developer.hashicorp.com/terraform/install)
* [Install Postman](https://www.postman.com/downloads/) for testing
* [Install Docker](https://docs.docker.com/engine/install/)
* [Microsoft.App](https://learn.microsoft.com/en-us/azure/container-apps/) Provider must be enabled
* `User Access Administrator` role must be assigned to build identity

![role](azure-user-role.png)

If this is your first time watching our content, we recommend starting with this video: [Azure + Terraform: Easy Setup](https://www.youtube.com/watch?v=j4aRjgH5H8Q). It provides a step-by-step guide to properly configure Terraform, Packer, and the AZ CLI.

## Download this Repository

```bash
git clone https://github.com/mamonaco1973/azure-rstudio-aks.git
cd azure-rstudio-aks
```

## Build the Code

Run [check_env](check_env.sh) to validate your environment, then run [apply](apply.sh) to provision the infrastructure.

```bash
~/azure-rstudio-aks$ ./apply.sh
NOTE: Running environment validation...
NOTE: Validating that required commands are found in your PATH.
NOTE: az is found in the current PATH.
NOTE: terraform is found in the current PATH.
NOTE: docker is found in the current PATH.
NOTE: jq is found in the current PATH.
NOTE: All required commands are available.
NOTE: Checking AWS cli connection.
NOTE: Successfully logged into AWS.
NOTE: Building Active Directory instance...
Initializing the backend...
```
