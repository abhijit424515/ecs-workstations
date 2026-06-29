# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Always-on [Hermes Agent](https://pypi.org/project/hermes-agent/) dev environments running as ECS services on a single EC2 host. Each top-level dir (`personal/`, `work/`) is one self-contained workstation. There is no application source here — this repo is infra glue: Dockerfile + ECS task def + entrypoint + secret-injection, deployed by one script.

## Commands

```bash
# Build image, push to ECR, register task def, create/update ECS service.
# Also decrypts SOPS secrets and writes them to the host EBS volume via SSM.
./build-and-deploy.sh <workstation>     # personal | work

# Encrypt a new/edited secrets file (run inside the workstation dir)
sops --encrypt --input-type yaml --output-type yaml secrets.yaml > secrets.yaml.sops && rm secrets.yaml

# Inspect a deployed service
aws ecs describe-services --cluster aegis-cluster --services <workstation>-devcontainer --profile personal

# Live shell into the running container (ECS Exec)
aws ecs execute-command --cluster aegis-cluster --task <task-id> --container devcontainer \
    --interactive --command /bin/bash --profile personal

# Terraform (per workstation, optional EFS provisioning)
cd <workstation>/terraform && terraform plan && terraform apply
```

Prereqs the deploy script assumes: AWS CLI logged in, Docker running, `sops` + KMS access, `jq`. `AWS_PROFILE` defaults to `personal`; override via env. There is **no test suite** — this is deploy-and-observe.

## Deploy pipeline (build-and-deploy.sh)

The single source of orchestration. Steps, in order:
1. **Decrypt secrets** — `sops -d` the workstation's `secrets.yaml.sops` → JSON, pull out `hermes_env`, `hermes_env_separator`, `aws_credentials`, `github`.
2. **Write secrets to host EBS** — base64-encode each, then `aws ssm send-command` to the fixed EC2 host (`EC2_INSTANCE`), which runs `scripts/write-secrets.py` to materialize files under `WORKSTATION_PATH` (default `/mnt/workstations/<workstation>`). Secrets never go into the image or the task def.
3. **ECR** — login to ECR Public, ensure repo `<workstation>-devcontainer` exists.
4. **Build + push** — image tagged with a UTC timestamp and `latest`.
5. **Task def** — `sed`-substitute tokens in `task-definition.json` → `/tmp/...`, then register. Token order matters: `WORKSTATION_PATH` is replaced **before** `WORKSTATION` (substring), then `IMAGE_TAG`.
6. **Service** — create (EC2 launch type, desired-count 1) or force-new-deployment if it already exists; always `--enable-execute-command`.

> Note: `write-secrets.py` is loaded from `personal/scripts/` regardless of which workstation you deploy (`SCRIPT_PATH` is hardcoded to `personal/`). The two `scripts/write-secrets.py` are intended to stay identical.

## How secrets reach the container

Image is stateless. The host EBS dir (`/mnt/workstations/<workstation>`) is bind-mounted to `/home/hermes` in the container (see `task-definition.json` `mountPoints`). `write-secrets.py` populates that dir on the host:
- `.hermes/.env` — Hermes env vars. **Appended** below a separator line (`hermes_env_separator`), not overwritten — content above the separator is preserved across deploys, content below is replaced. This lets manual host edits coexist with deploy-managed vars.
- `.aws/credentials`, `.gitconfig`, `.config/gh/hosts.yml` — overwritten each deploy.
- Finally `chown -R 1000:1000` the whole dir (container's `hermes` user is UID 1000).

So: editing `config.yaml` requires a rebuild (it's `COPY`d into the image); editing secrets only requires re-running the deploy (writes to EBS, then force-new-deployment picks them up).

## Per-workstation files

| File | Role |
|---|---|
| `Dockerfile` | python:3.11-slim base; installs AWS CLI v2, Terraform, gh, Docker CLI, Poetry, `hermes-agent`. Creates UID-1000 `hermes` user. `COPY`s `config.yaml` + entrypoint. |
| `config.yaml` | Hermes Agent config (model/provider, enabled tools, on-start skills) baked into the image. |
| `task-definition.json` | ECS task def **template** with `WORKSTATION`, `WORKSTATION_PATH`, `IMAGE_TAG` tokens. `networkMode: host`, mounts host EBS + docker socket. |
| `scripts/entrypoint.sh` | chowns `/workspace`, then `exec hermes gateway run --accept-hooks` (long-running Telegram gateway = the keep-alive process). |
| `scripts/write-secrets.py` | Runs **on the host** via SSM (not in the container). Materializes secrets onto EBS. |
| `secrets.yaml.example` | Template; copy → `secrets.yaml`, fill, encrypt, delete plaintext. |
| `terraform/` | Optional EFS One-Zone filesystem provisioning. Note: the task def currently bind-mounts a **host EBS path**, not EFS — terraform here is not wired into the deploy path. |

## Conventions

- **Secrets**: plaintext `secrets.yaml` is gitignored; only `secrets.yaml.sops` is committed. SOPS encrypts via the KMS key in `.sops.yaml`.
- **ECS Exec, not SSH**: shell access is via `aws ecs execute-command`. The container runs **no** in-container SSM agent — the ECS agent injects SSM binaries from the host at runtime; the `devcontainer-task-role` carries the `ssmmessages` perms.
- Hardcoded infra IDs live in `build-and-deploy.sh` (cluster `aegis-cluster`, EC2 host instance id, ECR registry `public.ecr.aws/l0b6e2f4`, region `ap-south-1`). Adding a new workstation = new top-level dir with the five per-workstation files; the script derives everything else from the dir name.
- Region split: ECR Public ops use `us-east-1`; everything else uses `ap-south-1`.
