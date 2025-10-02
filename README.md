# FARE - A T-REX Compliant Token System for Aptos

A comprehensive, modular smart contract system implementing the T-REX (Token for Regulated EXchanges) standard on the Aptos blockchain. This system provides full compliance with securities regulations while leveraging Aptos's unique capabilities for performance and safety.

## Overview

The T-REX compliant token system is designed to meet the requirements of regulated securities trading, providing:

- **Identity Management**: Onchain identity verification with KYC/AML compliance
- **Compliance Modules**: Pluggable compliance rules for transfer restrictions, country limitations, and investor type validation
- **T-REX Token**: Fully compliant fungible assets with built-in compliance hooks
- **DVP/DVE System**: Delivery vs Payment and Delivery vs Exchange functionality
- **Role-Based Access Control**: Granular permissions for different user types
- **Asset Recovery**: Mechanisms for frozen asset recovery and compliance enforcement

## Architecture

The system is built with a modular architecture, separating concerns into distinct modules:

```
sources/
├── identity/           # Identity management system
│   ├── onchain_identity.move
│   ├── claim_issuers.move
│   └── identity_storage.move
├── compliance/         # Compliance modules
│   ├── compliance_registry.move
│   ├── modular_compliance.move
│   ├── country_restrictions.move
│   └── transfer_rules.move
├── token/             # T-REX token implementation
│   ├── trex_token.move
│   ├── token_roles.move
│   └── token_information.move
├── dvp/               # DVP/DVE system
│   ├── dvp_manager.move
│   ├── dve_exchange.move
│   └── settlement.move
└── utils/             # Utilities and constants
    ├── access_control.move
    └── constants.move
```

## Key Features

### 1. Identity System

- **Onchain Identity**: Non-transferable identity objects bound to user addresses
- **Claim Management**: ERC-735 standard claims for KYC, AML, country, accreditation, etc.
- **Identity Recovery**: Multi-signature recovery mechanisms
- **Identity Freeze**: Ability to freeze/unfreeze identities for compliance

### 2. Compliance Modules

- **Transfer Restrictions**: Maximum transfer amounts, daily/monthly limits, transfer locks
- **Country Restrictions**: Whitelist/blacklist countries, bilateral restrictions
- **Balance Restrictions**: Maximum balance per holder, supply limits
- **Investor Type Restrictions**: Retail, accredited, institutional investor validation
- **Time-Based Restrictions**: Trading hours, transfer delays

### 3. T-REX Token

- **Compliance Hooks**: Automatic compliance checking on every transfer
- **Identity Integration**: KYC/AML verification before transfers
- **Forced Transfers**: Compliance officer asset recovery capabilities
- **Token Pause**: Emergency pause/unpause functionality
- **Supply Management**: Configurable supply caps and minting controls

### 4. DVP/DVE System

- **Delivery vs Payment**: Atomic swaps between tokens and payment
- **Delivery vs Exchange**: Exchange-specific compliance and settlement
- **Escrow Management**: Secure escrow for pending transactions
- **Settlement Delays**: Configurable settlement windows
- **Netting**: Batch settlement capabilities

### 5. Access Control

- **Role-Based Permissions**: Token owner, compliance officer, token agent roles
- **Time-Delayed Transfers**: Role transfer delays for security
- **Multi-Signature Support**: Critical operations require multiple approvals
- **Emergency Pause**: System-wide pause capabilities

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd aptos-FARE
```

2. Install dependencies:
```bash
aptos move install
```

3. Compile the contracts:
```bash
aptos move compile
```

4. Run tests:
```bash
aptos move test
```

## Usage

### 1. Initialize the System

```move
// Initialize all modules
access_control::initialize(admin);
onchain_identity::initialize(admin);
claim_issuers::initialize(admin);
trex_token::initialize(admin);
// ... other modules
```

### 2. Create Identities

```move
// Create identity for a user
let identity_object = onchain_identity::create_identity(
    user,
    constants::get_kyc_level_basic(),
    constants::get_investor_type_retail(),
    b"US", // Country code
    946684800 // Date of birth timestamp
);
```

### 3. Register Claim Issuers

```move
// Register a trusted claim issuer
claim_issuers::register_issuer(
    admin,
    issuer_address,
    string::utf8(b"Trusted Issuer"),
    string::utf8(b"https://issuer.com"),
    vector::empty(), // Allowed topics
    1000, // Daily claim limit
    true, // Can issue batch claims
    true  // Can revoke claims
);
```

### 4. Create T-REX Token

```move
// Create a new T-REX compliant token
let (token_address, metadata) = trex_token::create_trex_token(
    admin,
    string::utf8(b"Security Token"),
    string::utf8(b"SEC"),
    8, // Decimals
    string::utf8(b"Regulated Security Token"),
    string::utf8(b"https://token.com/icon.png"),
    string::utf8(b"https://token.com"),
    1000000000000000000, // Max supply
    true, // Supply cap enabled
    true, // Compliance enabled
    true, // Identity verification required
    constants::get_kyc_level_basic(),
    constants::get_investor_type_retail(),
    true, // Country restrictions
    true, // Transfer restrictions
    true  // Balance restrictions
);
```

### 5. Set Up Compliance

```move
// Initialize token compliance
modular_compliance::initialize_token_compliance(admin, token_address);

// Enable compliance modules
modular_compliance::enable_compliance_module(
    admin,
    token_address,
    constants::get_compliance_module_transfer_restrictions(),
    1, // Priority
    vector::empty() // Config data
);
```

### 6. Configure Transfer Restrictions

```move
// Set transfer restrictions for a user
transfer_rules::set_user_transfer_restrictions(
    admin,
    user_address,
    1000000000000000000, // Max transfer amount
    10000000000000000000, // Daily limit
    100000000000000000000, // Monthly limit
    10, // Daily transfer count
    100, // Monthly transfer count
    3600 // Transfer lock duration (seconds)
);
```

### 7. Create DVP Order

```move
// Create a DVP order
let order_id = dvp_manager::create_dvp_order(
    seller,
    buyer,
    token_address,
    100000000000000000, // Token amount
    100000000, // Payment amount
    payment_token_address,
    timestamp::now_seconds() + 86400 // Expiry
);
```

### 8. Execute DVP Order

```move
// Execute the DVP order
dvp_manager::execute_dvp_order(buyer, order_id);
```

## Compliance Features

### Identity Verification

- **KYC Levels**: None, Basic, Enhanced, Full
- **Investor Types**: Retail, Accredited, Institutional, Professional
- **Country Codes**: ISO 3166-1 alpha-2 format
- **Age Verification**: Date of birth validation
- **PEP Status**: Politically Exposed Person screening
- **Sanctions Check**: OFAC and other sanctions screening

### Transfer Restrictions

- **Amount Limits**: Maximum transfer per transaction
- **Volume Limits**: Daily and monthly transfer volumes
- **Count Limits**: Maximum number of transfers per period
- **Time Locks**: Transfer delays after certain actions
- **Trading Hours**: Restricted trading windows

### Country Restrictions

- **Whitelist/Blacklist**: Country-based transfer controls
- **Bilateral Restrictions**: Country-to-country limitations
- **Jurisdiction Rules**: Regional compliance requirements
- **Sanctions Compliance**: Automatic sanctions screening

### Balance Restrictions

- **Maximum Balance**: Per-holder balance limits
- **Supply Limits**: Percentage of total supply per holder
- **Investor Count**: Maximum number of token holders
- **Minimum Balance**: Required minimum holdings

## Security Features

### Access Control

- **Role-Based Permissions**: Granular access control
- **Time Delays**: Role transfer delays for security
- **Multi-Signature**: Critical operations require multiple approvals
- **Emergency Pause**: System-wide pause capabilities

### Asset Protection

- **Account Freeze**: Individual account freezing
- **Partial Freeze**: Selective operation restrictions
- **Asset Recovery**: Frozen asset recovery mechanisms
- **Forced Transfers**: Compliance officer transfer capabilities

### Audit Trail

- **Comprehensive Events**: All operations emit events
- **Transfer History**: Complete transfer records
- **Compliance Logs**: All compliance checks logged
- **Admin Actions**: All administrative actions tracked

## Testing

The system includes comprehensive tests covering:

- **Unit Tests**: Individual module functionality
- **Integration Tests**: Cross-module interactions
- **Compliance Tests**: Compliance rule validation
- **Security Tests**: Access control and security features
- **End-to-End Tests**: Complete workflow validation

Run tests with:
```bash
aptos move test
```

## Deployment

### Devnet Deployment ✅

The FARE system has been successfully deployed to Aptos Devnet using a split package approach to overcome the 60KB transaction size limit.

#### Deployment Details

**Account Address**: `0x47ac98d0c7f09ae31de82ecf3301b1849b61004ce43529f13b85efc95380fc76`

**Deployed Packages**:

1. **Core Package** (Transaction: `0x03f30523f02f1ee76d7ddc0d0548f9724325652cfcab6fac6c56e712c05902c8`)
   - Modules: `constants`, `access_control`, `identity_storage`, `onchain_identity`, `claim_issuers`, `compliance_registry`, `modular_compliance`, `transfer_rules`, `country_restrictions`
   - Size: 47,009 bytes
   - Gas Used: 10,269

2. **Token Package** (Transaction: `0x2fbae0b1b568f8a9728c858715e8e644ead6fbabb132db1f197729006216745c`)
   - Modules: `trex_token`, `token_information`, `token_roles`
   - Size: 29,832 bytes
   - Gas Used: 8,279

#### Deployment Strategy

Due to the comprehensive nature of the T-REX system, the original package exceeded Aptos's 60KB transaction size limit. The solution was to split the modules into logical packages:

- **Core Package**: Identity, compliance, and utility modules
- **Token Package**: T-REX token and related token management modules
- **DVP Package**: Delivery vs Payment/Exchange modules (planned)

#### Verification

You can verify the deployment on Aptos Explorer:
- [Core Package Transaction](https://explorer.aptoslabs.com/txn/0x03f30523f02f1ee76d7ddc0d0548f9724325652cfcab6fac6c56e712c05902c8?network=devnet)
- [Token Package Transaction](https://explorer.aptoslabs.com/txn/0x2fbae0b1b568f8a9728c858715e8e644ead6fbabb132db1f197729006216745c?network=devnet)

#### Usage on Devnet

To interact with the deployed contracts:

```bash
# Initialize the system
aptos move run --function-id 0x47ac98d0c7f09ae31de82ecf3301b1849b61004ce43529f13b85efc95380fc76::access_control::initialize

# Create an identity
aptos move run --function-id 0x47ac98d0c7f09ae31de82ecf3301b1849b61004ce43529f13b85efc95380fc76::onchain_identity::create_identity \
  --args u8:1 u8:1 string:"US" u64:946684800

# Create a T-REX token
aptos move run --function-id 0x47ac98d0c7f09ae31de82ecf3301b1849b61004ce43529f13b85efc95380fc76::trex_token::create_trex_token \
  --args string:"TestToken" string:"TEST" u8:8 string:"Test Token" string:"" string:"" u64:1000000000000000000 bool:true bool:true bool:true u8:1 u8:1 bool:true bool:true bool:true
```

### Mainnet Deployment

1. **Compile Contracts**:
```bash
aptos move compile
```

2. **Deploy Modules** (Note: May require split package approach):
```bash
aptos move publish --override-size-check --included-artifacts none
```

3. **Initialize System**:
```bash
aptos move run --function-id <module>::initialize
```

### Testnet Deployment

1. **Switch to Testnet**:
```bash
aptos config set-profile default --profile testnet
```

2. **Deploy to Testnet**:
```bash
aptos move publish --profile testnet --override-size-check --included-artifacts none
```


## ⚠️ Important Implementation Disclaimer

**This implementation does NOT use the Aptos Fungible Asset (FA) standard for balance tracking or transfer logic.**

The current version uses a completely custom balance management system with:
- Custom `user_balances` table for tracking token balances
- Custom transfer logic that bypasses the standard FA framework  
- Custom minting system that directly updates internal balance tables
- Custom DVP transfer functions that don't integrate with FA standards

**This is a temporary implementation for testing and development purposes.** For production use, this should be refactored to properly integrate with the Aptos Fungible Asset standard.

### Current Limitations:
- ❌ Not compatible with standard Aptos FA wallets
- ❌ Cannot be used with standard FA transfer functions
- ❌ Balance tracking is isolated from the Aptos ecosystem
- ❌ No integration with Aptos primary fungible stores
- ❌ Custom implementation may have security implications

### Future Roadmap:
- ✅ Refactor to use proper Aptos Fungible Asset standard
- ✅ Integrate with primary fungible stores
- ✅ Support standard FA wallet compatibility
- ✅ Implement proper FA transfer mechanisms
