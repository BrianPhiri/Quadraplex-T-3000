# Quadraplex-T-3000
An overly complicated homelab setup that also acts as documentation and templete for others (only reason it's public).
It installs **Docker**, configures **Traefik** as a reverse proxy, and orchestrates application stacks including:

- **Media services (Arr stack)** – Radarr, Sonarr, Lidarr, etc.  
- **Monitoring tools** – Prometheus, cAdvisor, Grafana, Uptime Kuma.  
- **Management utilities** – Portainer, Vaultwarden, and helper services.  

All services are grouped into stacks, making it easy to enable or disable specific apps and extend the setup with new deployments.  

---

## Folder Structure
my-stack-ansible/
├── ansible.cfg # Ansible configuration
├── Makefile # Task shortcuts
├── README.md # Documentation
├── .gitignore # Ignore rules
│
├── inventory/ # Inventory definitions
│ ├── hosts.yml
│ ├── group_vars/ # Group-specific variables
│ └── host_vars/ # Host-specific variables
│
├── playbooks/ # Playbooks for different stacks/tasks
│ ├── site.yml
│ ├── deploy-media-stack.yml
│ ├── deploy-management-stack.yml
│ ├── update-stack.yml
│
├── roles/ # Modular Ansible roles
│ ├── docker/ # Docker installation/config
│ ├── traefik/ # Reverse proxy setup
│ ├── media-stack/ # Media apps (Arr stack)
│ ├── utility-stack/ # Monitoring/utility apps
│ ├── backup/ # Backup automation
│ └── secrets-management/ # Vaultwarden and secrets
│
├── secrets/ # Encrypted secrets & scripts
├── files/ # SSL certs, scripts, dashboards
├── templates/ # Systemd and Docker templates
└── vars/ # Shared variables (versions, networks)

## Tools Used
- **[Ansible](https://www.ansible.com/):** Provisioning, configuration, deployment.  
- **[Make](https://www.gnu.org/software/make/):** Task runner for common operations.  
- **Bash:** Utility scripts for secrets, backups, and host operations.

## What It Does
1. **System Prep**  
   - Installs prerequisites.  
   - Configures Docker daemon and networking.  

2. **Reverse Proxy**  
   - Deploys Traefik for HTTPS and routing.  
   - Manages TLS, middlewares, and service discovery.  

3. **Media Stack**  
   - Deploys Radarr, Sonarr, Lidarr, and related services.  

4. **Monitoring & Utilities**  
   - **Prometheus & cAdvisor** – metrics collection.  
   - **Grafana** – dashboards and visualization.  
   - **Uptime Kuma** – uptime monitoring.  
   - **Portainer** – Docker management UI.  

5. **Secrets & Backup**  
   - Vaultwarden for secure storage.  
   - Automated backup and restore playbooks.  

---
## How to Run

### 1. Prerequisites
- Control machine:  
  - **Ansible ≥ 2.13**  
  - **Python ≥ 3.8**  
  - `make` installed  
- Managed hosts:  
  - Linux (tested on Debian/Ubuntu)  
  - SSH access  

### 2. Customize host
- Edit inventory/hosts.yml and adjust group_vars/ and host_vars/ for your environment.

### 3. Deploy using make
`make deploy`
