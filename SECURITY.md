# Security Policy

## Reporting a vulnerability

Please report security vulnerabilities privately through GitHub's **Report a
vulnerability** link on the repository Security tab. Do not open a public issue
for an undisclosed vulnerability.

Include the affected version, macOS version, reproduction steps, expected and
observed behavior, and any relevant logs with secrets removed.

We will acknowledge valid reports and coordinate a fix and disclosure timeline
with the reporter.

## Scope and limitations

PrivyLock is a user-space macOS utility. It is designed as a privacy and
convenience layer, not as a boundary against a local administrator or root
process. Authentication is delegated to macOS LocalAuthentication; PrivyLock
does not store Touch ID data or Mac passwords.
