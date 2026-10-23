# Pip Guides questions

## What problem does it solve?

Turn a process into a locally stored guide with editable steps and pictures. Write a guide manually, use the built-in practice window, or explicitly select an external window for click capture. External capture acceptance and current limitations are listed in [verification](../PUBLIC-VERIFICATION.md).

## What runs on my Mac?

A native SwiftUI/AppKit application for macOS14+. It has no third-party package dependencies, AI model, account, hosted runtime or paid API. Apple Silicon is the verified development platform; other configurations are unverified.

## Which edition is included?

This repository contains only the Neutral Core Replica (`baseline`). No Pip or enhanced editions are included. See the [edition map](EDITIONS.md).

## Where are guides and pictures stored?

Each edition uses its own local Application Support folder. Portable `.pipguide` files embed PNG pictures. HTML and Markdown exports embed images rather than referring to a hosted image service. Some Markdown viewers block embedded data images; use HTML for a portable viewing file. PDF is also available.

## What permissions are needed?

External capture needs the user's Screen Recording and Accessibility grants for that exact application. Manual editing and the built-in practice workflow work without those grants. The app must never bypass native consent. See current [verification](../PUBLIC-VERIFICATION.md) rather than assuming a grant or successful capture on another Mac.

## Does redaction remove the original pixels?

Solid redaction replaces pixels in the saved image. A successful privacy edit also updates the app's recovery copy. Earlier exports, OS snapshots and external backups remain separate copies. Blur can leave information readable; review every image before sharing. Custom password controls cannot be universally certified.

## Can I import Scribe or Tango projects?

No proprietary project import or account integration is implemented. See [moving existing instructions](MIGRATION.md) for the supported manual route. This is an independent project with original branding and MIT source, without affiliation or a complete-parity claim.

## Is a downloaded build notarised?

Current packages use local ad-hoc signatures. They are experimental and are not Developer ID signed or notarised. Build from source using the [setup instructions](../README.md); do not disable system security globally.
