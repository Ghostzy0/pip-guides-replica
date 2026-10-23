# Set up Guides Replica

Build the Neutral Core Replica edition in this repository. Do not infer that another product or edition is included.

```sh
swift test
./scripts/build-app.sh baseline
codesign --verify --deep --strict 'dist/Guides Replica.app'
open 'dist/Guides Replica.app'
```

Use the built-in sample practice window to check the synthetic workflow. External capture requires the user's native Screen Recording and Accessibility grants. Never bypass macOS consent or collect personal screenshots. Packages are locally ad-hoc signed and are not notarised.
