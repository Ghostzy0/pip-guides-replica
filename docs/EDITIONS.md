# Guides Replica edition map

This repository publishes the Neutral Core Replica product only. Its default and only edition is `baseline`. The local package includes the shared Guides engine with the original neutral reference-inspired composition; documented fidelity gaps remain in [public verification](../PUBLIC-VERIFICATION.md).

## Build

```sh
./scripts/build-app.sh
```

`distribution.json` is the machine-readable source of the default edition and allowed variant list. `SOURCE-INPUTS.json` records hashes of original pre-export inputs; expected public-export transformations may make those hashes differ from the final output bytes. `SOURCE-MANIFEST.json` records hashes of the final public files. `SOURCE-PROVENANCE.json` records the product identity and both manifest digests. It contains no private repository origin or revision.
