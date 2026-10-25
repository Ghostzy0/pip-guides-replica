# Set up Guides Replica

Build the Neutral Core Replica edition in this repository. Do not infer that another product or edition is included.

```sh
swift test
./scripts/build-app.sh baseline
codesign --verify --deep --strict 'dist/Guides Replica.app'
open 'dist/Guides Replica.app'
```

Use the built-in sample practice window to check the synthetic workflow. External capture requires the user's native Screen Recording and Accessibility grants. Never bypass macOS consent or collect personal screenshots. Packages are locally ad-hoc signed and are not notarised.

## Optional signing and permission limits

By default builds use an ad-hoc signature. On a Mac that already has a valid Apple Development identity, `PIP_GUIDES_SIGNING_IDENTITY` or the ignored `.local-signing-identity` file may select the existing identity. No certificate or key is supplied here. The selector fails closed for an unavailable or invalid identity. A repeated identity can keep a stable signing requirement, but this does not promise that macOS Screen Recording or Accessibility grants carry over to a new build. Inspect the result for the exact running app; never bypass consent or weaken capture checks.

The source candidate includes a read-only **Check access** control that reports Screen Recording and Accessibility status for the running build. It makes no request, opens no Settings panel and enumerates no windows. Native verification for this new control is pending.
