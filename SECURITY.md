# Security policy

Watcher intercepts and decrypts network traffic, so security reports matter.

## Supported versions

Only the latest release receives security fixes.

## Reporting a vulnerability

Please do not open a public issue. Report privately through [GitHub security advisories](https://github.com/mkemalgokce/watcher/security/advisories/new), or contact the maintainer, [@mkemalgokce](https://github.com/mkemalgokce), through the contact details on their GitHub profile.

Include the affected version, the steps to reproduce and the impact. You can expect an acknowledgement within a week.

## Scope

In particular:

- handling of the root CA private key and generated certificates;
- anything that lets a remote client use or reconfigure the proxy without access control;
- path traversal through Map Local or scripting file access;
- leaks of captured traffic, credentials or settings (`~/.watcher/settings.json`).
