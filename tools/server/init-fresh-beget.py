#!/usr/bin/env python3
"""Prepare a fresh, explicitly authorized beta database. Never import/reset Floot."""
import json, os, pathlib, secrets, subprocess, sys

if os.geteuid() != 0:
    sys.exit('Run as root on the authorized Beget host')
source = pathlib.Path(sys.argv[1]).resolve()
state = pathlib.Path('/var/lib/muwa/fresh-database.json')
envfile = pathlib.Path('/etc/muwa/backend.env')

def pg(sql, database='postgres'):
    result = subprocess.run(['runuser','-u','postgres','--','psql','-X','-v','ON_ERROR_STOP=1','-At','-d',database], input=sql, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError('PostgreSQL provisioning failed; no credentials printed')
    return result.stdout.strip()

exists = pg("SELECT datname FROM pg_database WHERE datname='muwa';")
if exists:
    if state.exists() and envfile.exists():
        print(json.dumps({'database':'muwa','state':'already_prepared','secretsPrinted':False}))
        sys.exit(0)
    sys.exit('Existing muwa database requires review; no overwrite performed')
if pg("SELECT rolname FROM pg_roles WHERE rolname IN ('muwa_owner','muwa_app','muwa_audit');"):
    sys.exit('Existing Muwa roles require review; no passwords changed')
subprocess.run(['useradd','--system','--user-group','--home-dir','/var/lib/muwa-app','--shell','/usr/sbin/nologin','muwa'],check=True)
subprocess.run(['install','-d','-m','0700','-o','muwa','-g','muwa','/var/lib/muwa-app','/var/lib/muwa-app/media'],check=True)
subprocess.run(['install','-d','-m','0700','/etc/muwa','/var/lib/muwa'],check=True)
password, audit_password = secrets.token_hex(32), secrets.token_hex(32)
pg("CREATE ROLE muwa_owner NOLOGIN; CREATE ROLE muwa_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE CONNECTION LIMIT 10 PASSWORD '"+password+"'; CREATE ROLE muwa_audit LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE CONNECTION LIMIT 16 PASSWORD '"+audit_password+"';")
pg('CREATE DATABASE muwa OWNER muwa_owner;')
pg('CREATE DATABASE muwa_audit OWNER muwa_audit;')
files=['base-schema.sql','admin-migration.sql','security-migration.sql','premium-migration.sql','migration.sql','telegram-import-migration.sql']
content='BEGIN; SET ROLE muwa_owner;\n'+ '\n'.join((source/'backend'/name).read_text() for name in files)+'\nCOMMIT;'
pg(content,'muwa')
pg('REVOKE ALL ON DATABASE muwa FROM PUBLIC; GRANT CONNECT ON DATABASE muwa TO muwa_app;','muwa')
pg('REVOKE CREATE ON SCHEMA public FROM PUBLIC; GRANT USAGE ON SCHEMA public TO muwa_app; GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO muwa_app; GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO muwa_app; ALTER DEFAULT PRIVILEGES FOR ROLE muwa_owner IN SCHEMA public GRANT SELECT,INSERT,UPDATE,DELETE ON TABLES TO muwa_app; ALTER DEFAULT PRIVILEGES FOR ROLE muwa_owner IN SCHEMA public GRANT USAGE,SELECT ON SEQUENCES TO muwa_app;','muwa')
values={'MUWA_DATABASE_URL':'postgresql://muwa_app:'+password+'@127.0.0.1:5432/muwa','JWT_SECRET':secrets.token_hex(48),'MUWA_STORAGE_SECRET':secrets.token_hex(48),'MUWA_PUBLIC_ORIGIN':'https://93.188.187.96','MUWA_STORAGE_ROOT':'/var/lib/muwa-app/media','MUWA_BETA_USER_IDS':'1','MUWA_API_PORT':'3000','MUWA_OWNER_EMAIL':'randey.pubg@gmail.com','MUWA_OWNER_SETUP_LINK_FILE':'/var/lib/muwa/owner-setup-link.txt','NODE_ENV':'production'}
for path, entries in [(envfile,values),(pathlib.Path('/etc/muwa/audit.env'),{'MUWA_TEST_DATABASE_URL':'postgresql://muwa_audit:'+audit_password+'@127.0.0.1:5432/muwa_audit'})]:
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as out:
        out.write('\n'.join(key+'='+value for key,value in entries.items())+'\n')
state.write_text(json.dumps({'database':'muwa','migrationFiles':files,'catalog':'empty','oldFlootTouched':False,'secretsPrinted':False},indent=2)+'\n')
state.chmod(0o600)
print(json.dumps({'database':'muwa','state':'prepared','tables':int(pg("SELECT count(*) FROM information_schema.tables WHERE table_schema='public';",'muwa')),'secretsPrinted':False}))
