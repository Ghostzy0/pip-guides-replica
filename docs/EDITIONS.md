# Guides Replica edition map

This repository publishes the Neutral Core Replica product only. Its default and only edition is `baseline`. The local package includes the shared Guides engine with the original neutral reference-inspired composition; documented fidelity gaps remain in [public verification](../PUBLIC-VERIFICATION.md).

## Build

```sh
./scripts/build-app.sh
```

`distribution.json` is the machine-readable source of the default edition and allowed variant list. `SOURCE-PROVENANCE.json` records the product identity, source-input manifest hashes and public-file manifest hash. It contains no private repository origin or revision.
