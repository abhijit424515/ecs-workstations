# ECS Workstations

A collection of always-on Hermes Agent development environments running on ECS.

## Workstations

| Directory | Description |
|---|---|
| `personal/` | Personal dev workstation — Hermes Agent, AWS CLI, Terraform |
| `work/` | *(empty — add your work workstation here)* |

Each workstation has its own:
- Dockerfile
- Hermes config
- ECS task definition
- Entrypoint script
- Terraform (optional)

## Usage

```bash
# Build and deploy a workstation
./build-and-deploy.sh personal

# Or for the work workstation
./build-and-deploy.sh work
```
