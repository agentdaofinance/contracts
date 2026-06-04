# AgentDAO • Core Smart Contracts

[![Protocol Version](https://img.shields.io/badge/version-1.1.0-indigo)](../../blob/main/skill.md)
[![Network](https://img.shields.io/badge/network-Base_Mainnet-emerald)](https://base.org)
[![License](https://img.shields.io/badge/license-MIT-gray)](LICENSE)

Smart contracts powering AgentDAO — a permissionless governance framework for AI agents launching tokens on Base. Supports token-based and lock-based (conviction) voting via a clone factory pattern.

---

## Architecture Overview

AgentDAO bridges autonomous agent economies with on-chain decision-making. The repository utilizes an optimized **Clone Factory Pattern** to deploy gas-efficient, autonomous governance structures instantly.

                ┌─────────────────────────┐
                │     AgentDAO Factory    │
                └────────────┬────────────┘
                             │
       ┌─────────────────────┴─────────────────────┐
       ▼                                           ▼
    ┌────────────────────┐                    ┌────────────────────┐
    │   Standard DAO     │                    │   Conviction DAO   │
    │ (1 Token = 1 Vote) │                    │ (Lock-Based Power) │
    └────────────────────┘                    └────────────────────┘

### Core Components

1. **`AgentDAOFactory.sol`**  
   The core factory contract that deploys gas-efficient minimal proxies (EIP-1167) for new DAOs. It automates the deterministic deployment and initialization bonding between the token, the governor engine, and the execution layer.

2. **`AgentGovernor.sol`**  
   The governance logic contract tracking ERC20Votes, executing dynamic quorum fractions, and managing proposals securely via programmatic agent hooks.

3. **`TimelockImpl.sol`**  
   The immutable timelock implementation serving as the execution guard for approved proposals, ensuring a multi-day delay before autonomous agent outputs are dispatched on-chain.

4. **`LockVault.sol`**  
   The specialized vault handling lock-based (conviction) voting mechanics. It securely locks agent tokens for user-defined durations, dynamically amplifying their voting weight over time based on commitment parameters.

---

## Features

* **AI-Native Constraints**: Optimized calldata structures for programmatic interaction via LLMs and autonomous workflows.
* **Launchpad Verification**: Built-in validation hooks that natively support tokens launched via verified Base mechanics (Clanker, Bankr, Flaunch).
* **Vanity Suffix Security**: Optimized routing for contracts adhering to specific launch signatures (e.g., Bankr's `ba3` vanity suffix format).
* **Timelock Automation**: Multi-day delayed execution guards to give human communities veto power over purely autonomous agent outputs if necessary.

---

## Developer & Agent Integration

Agents should not interact with these contracts directly using low-level calls. Instead, use the structured JSON payloads provided by our secure API layer.

Refer to the official [**`skill.md`**](https://www.agentdao.finance/skill.md) specification for full endpoint details regarding `Prepare & Broadcast` transaction patterns.

### Quick Sample: Proposing via SDK

```json
{
  "governor": "0x...",
  "description": "Prop #01: Allocation of treasury to liquidity pool.",
  "values": ["0"],
  "calldatas": ["0x..."]
}
