# Security Policy

## Supported Versions

Security fixes are provided for the latest released version.

## Scope and Threat Model

`baked_file_system` embeds files into a binary at compile time. The compile-time
inputs (the folder path passed to `bake_folder`, the files inside it, and the
build environment) are **trusted**. A developer who bakes a malicious or
sensitive file into their own binary has not found a vulnerability here.

In scope:

- Reading a baked file returns wrong, truncated, or other files' bytes.
- A path lookup at runtime escapes the baked file set, or resolves to a file the
  caller did not ask for.
- Attacker-controlled input to a runtime API (`get`, `get?`, the HTTP static
  handler) causes memory unsafety, a crash, or unbounded resource use.
- The HTTP static file handler serves a file outside the baked set, or leaks
  paths or contents it should not.
- Decompression of embedded data can be driven into unbounded memory or CPU use
  by a runtime input.

Out of scope:

- Anything requiring control of the build machine, the baked folder, or the
  macro arguments.
- Baking secrets into a public binary. That is intended behavior of an embedding
  library, documented in the README.
- Resource use proportional to what the developer chose to bake.

## Reporting a Vulnerability

Please report suspected vulnerabilities privately to david@schovi.cz. Do not open a public issue.

Include the affected version, impact, reproduction steps or a proof of concept, and any suggested remediation. Add the contact details and credit you want used in an advisory.

You should receive an acknowledgement within seven days.

## Disclosure Terms

This project is maintained by one person in their spare time. These terms apply
to every reporter, including security vendors and CVE Numbering Authorities:

- Reports stay private until a fix is released, or for 90 days from
  acknowledgement, whichever comes first. Ask if you need a different window.
- Severity, CVSS score, and affected version ranges are agreed with the
  maintainer before a CVE is assigned or published. Findings outside the scope
  above will be disputed.
- Credit is given as the reporter requests.
