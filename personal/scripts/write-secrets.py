#!/usr/bin/env python3
import os, base64, sys

env_b64 = sys.argv[1]
sep_b64 = sys.argv[2]
creds_b64 = sys.argv[3]

env_content = base64.b64decode(env_b64).decode()
sep = base64.b64decode(sep_b64).decode()
creds = base64.b64decode(creds_b64).decode()

env_file = '/mnt/workstation/.hermes/.env'
creds_file = '/mnt/workstation/.aws/credentials'

os.makedirs('/mnt/workstation/.hermes', exist_ok=True)
os.makedirs('/mnt/workstation/.aws', exist_ok=True)

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

with open(creds_file, 'w') as f:
    f.write(creds)
    if not creds.endswith('\n'):
        f.write('\n')

os.system('chown -R 1000:1000 /mnt/workstation/.hermes /mnt/workstation/.aws 2>/dev/null || true')
os.system('chmod 600 /mnt/workstation/.aws/credentials /mnt/workstation/.hermes/.env')

print('=== .env ===')
print(open(env_file).read())
print('=== .aws/credentials (masked) ===')
c = open(creds_file).read()
print(c[:80])
