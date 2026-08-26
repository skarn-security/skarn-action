# Security policy

## Reporting a vulnerability

Report suspected vulnerabilities privately, not in a public issue. Use GitHub's private vulnerability reporting on this repository (the Security tab, "Report a vulnerability"), or the contact on https://getskarn.com. Expect an acknowledgement within one business day.

## Scope

This repository is the Skarn GitHub Action: configuration and a thin wrapper that runs the Skarn CLI in CI. It does not contain the Skarn detection engine, its rules, or the binary - those are fetched at run time and maintained separately. Vulnerabilities in the Skarn scanner itself are handled through https://getskarn.com.
