# Security notes

## What this project never does
- No telemetry, no analytics, no outbound calls except the remote hosts you configure.
- No passwords are stored or transmitted. Remote monitoring uses your own OpenSSH client
  with key-based authentication (`BatchMode=yes`, `PasswordAuthentication` never requested).
- No network listener is opened on the monitored host. The probe is a POSIX shell script
  that prints `key=value` lines; it is piped over an existing SSH connection.

## Remote host onboarding
1. **Trust the host key first.** `ssh-keyscan` output is appended to your
   `%USERPROFILE%\.ssh\known_hosts`; `StrictHostKeyChecking=yes` stays enabled, so a
   host whose key changes will refuse to connect rather than silently accept a new key.
2. **Deploy the probe** over the same SSH session (`cat > ~/.sysmon.sh && chmod 700`).
3. **Test the connection** before saving.

## Never commit
`sysmon.json` holds your host list and window coordinates. It is git-ignored; if you
fork this project, keep it that way. Signing keys (`*.pfx`, `cert` stores) and any
`evidence/` output (screenshots, logs) must stay local.

## Reporting
Open a private security advisory in the repository instead of a public issue.
