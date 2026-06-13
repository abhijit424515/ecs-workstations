#!/usr/bin/env python3
import os, base64, sys

env_b64 = sys.argv[1]
sep_b64 = sys.argv[2]
creds_b64 = sys.argv[3]
github_b64 = sys.argv[4]
workstation_path = sys.argv[5] if len(sys.argv) > 5 else None
if workstation_path is None:
    print('ERROR: workstation_path argument required', file=sys.stderr)
    sys.exit(1)

env_content = base64.b64decode(env_b64).decode()
sep = base64.b64decode(sep_b64).decode()
creds = base64.b64decode(creds_b64).decode()
github_config = base64.b64decode(github_b64).decode()

env_file = f'{workstation_path}/.hermes/.env'
creds_file = f'{workstation_path}/.aws/credentials'

os.makedirs(f'{workstation_path}/.hermes', exist_ok=True)
os.makedirs(f'{workstation_path}/.aws', exist_ok=True)

# --- .env with separator ---
if os.path.exists(env_file):
    with open(env_file) as f:
        lines = f.readlines()
else:
    lines = []

new_lines = []
found = False
for line in lines:
    if line.rstrip('\n') == sep:
        found = True
        break
    new_lines.append(line)

if not found:
    if new_lines and new_lines[-1].strip():
        new_lines.append('\n')
    new_lines.append(sep + '\n')

new_lines.append(env_content)
if not env_content.endswith('\n'):
    new_lines.append('\n')

with open(env_file, 'w') as f:
    f.writelines(new_lines)

# --- AWS credentials ---
with open(creds_file, 'w') as f:
    f.write(creds)
    if not creds.endswith('\n'):
        f.write('\n')

# --- GitHub config (write to EBS, container picks up from home) ---
git_user = None
git_email = None
gh_token = None

for line in github_config.strip().split('\n'):
    if ':' in line:
        k, v = line.split(':', 1)
        k = k.strip()
        v = v.strip()
        if k == 'user':
            git_user = v
        elif k == 'email':
            git_email = v
        elif k == 'token':
            gh_token = v

home = workstation_path

# Write .gitconfig
if git_user and git_email:
    print(f'=== Writing git config: {git_user} / {git_email} ===')
    gitconfig = f'[user]\n\tname = {git_user}\n\temail = {git_email}\n'
    if gh_token:
        gitconfig += '[credential]\n\thelper = !gh auth git-credential\n'
    with open(f'{home}/.gitconfig', 'w') as f:
        f.write(gitconfig)
    os.chmod(f'{home}/.gitconfig', 0o644)
    print('  .gitconfig written')

# Write gh hosts config
if gh_token:
    print('=== Writing gh auth config ===')
    gh_dir = f'{home}/.config/gh'
    os.makedirs(gh_dir, exist_ok=True)
    gh_hosts = f'github.com:\n    user: {git_user or "unknown"}\n    oauth_token: {gh_token}\n    git_protocol: https\n'
    with open(f'{gh_dir}/hosts.yml', 'w') as f:
        f.write(gh_hosts)
    os.chmod(f'{gh_dir}/hosts.yml', 0o600)
    print('  gh hosts.yml written')

# --- Verification ---
print('=== .env ===')
print(open(env_file).read())
print('=== .aws/credentials (masked) ===')
c = open(creds_file).read()
print(c[:80])
if git_user:
    print(f'=== git user.name: {git_user} ===')
    print(f'=== git user.email: {git_email} ===')

# --- Fix ownership (EBS, container's hermes user is UID 1000) ---
# Whole EBS root must be writable — chown everything
print('=== Fixing ownership (chown 1000:1000 on whole EBS) ===')
os.system(f'chown -R 1000:1000 {workstation_path} 2>/dev/null || true')
print('  done')
