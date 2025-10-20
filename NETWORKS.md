# Official Platformless AI Networks & FAB Token

**Canonical Notice Repo** for network and token designations used by the Platformless AI project.

> This file constitutes “public notice” for purposes of the Business Source License 1.1 used across Fabstir repos.
> The **most recent entry for a given network supersedes prior entries**. Git history is the audit trail.

---

## How to read this file

- **Status**: `Official`, `Planned`, `Deprecated`, or `Testing`.
- **FAB Token**:
  - `Canonical` — primary token contract for this network (or its canonical bridged form).
  - `Test` — non-canonical test token.
  - Use `TBA` until deployment, then replace with the contract address(es).
- **Notes**: Use for constraints (e.g., “testing only”, “no payments”), upgrade paths, or deprecations.

---

## Current Designations

### Base Sepolia (testnet)

- **Network**: Base Sepolia
- **Chain ID**: `84532`
- **Status**: **Testing**
- **FAB Token**:
  - **Canonical**: `TBA` (test canonical once deployed)
  - **Test**: `TBA`
- **Effective**: 2025-10-20
- **Notes**: For pre-mainnet functionality testing only. Not for production payments.

---

### Base (mainnet)

- **Network**: Base
- **Chain ID**: `8453`
- **Status**: **Planned**
- **FAB Token**:
  - **Canonical**: `TBA` (mainnet)
- **Effective**: TBA
- **Notes**: Target primary L2 for production. Entry here will be updated at token deployment.

---

### opBNB (mainnet)

- **Network**: opBNB
- **Chain ID**: `204`
- **Status**: **Planned**
- **FAB Token**:
  - **Canonical (bridged)**: `TBA` (canonical bridge designation to be published)
- **Effective**: TBA
- **Notes**: Will follow canonical bridge rules defined below.

---

## Canonical Bridging Rules

1. **Canonical FAB** on a non-origin chain must reference an **official bridge** designated by Fabstir.
2. The canonical bridged address becomes the **FAB Token (Canonical)** for that network.
3. Any alternative bridge or wrapped token **is not** considered canonical unless explicitly listed here.

---

## Deprecation Policy

- A network may be marked **Deprecated** with a future **Effective** date.
- After that date, it is no longer an **Official Network** for purposes of pre-Change Date Production Use under the BUSL license.
- Prior activity remains governed by the license terms effective at the time of use.

---

## JSON Snapshot (machine-readable)

```json
{
  "version": "1.0.0",
  "updated": "2025-10-20",
  "networks": [
    {
      "name": "Base Sepolia",
      "chainId": 84532,
      "status": "Testing",
      "fabToken": {
        "canonical": "TBA",
        "test": "TBA"
      },
      "effective": "2025-10-20",
      "notes": "Pre-mainnet functionality testing only; not for production payments."
    },
    {
      "name": "Base",
      "chainId": 8453,
      "status": "Planned",
      "fabToken": {
        "canonical": "TBA"
      },
      "effective": "TBA",
      "notes": "Target primary L2 for production. Updated upon token deployment."
    },
    {
      "name": "opBNB",
      "chainId": 204,
      "status": "Planned",
      "fabToken": {
        "canonical": "TBA"
      },
      "effective": "TBA",
      "notes": "Canonical bridge designation to be published."
    }
  ],
  "bridgingRules": [
    "Canonical FAB on a non-origin chain must reference an official bridge designated by Fabstir.",
    "The canonical bridged address becomes the FAB Token (Canonical) for that network.",
    "Alternative bridges/wrappers are non-canonical unless explicitly listed here."
  ]
}
```
