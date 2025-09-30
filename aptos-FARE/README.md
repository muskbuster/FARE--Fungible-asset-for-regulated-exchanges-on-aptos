# T-REX Compliant Token System for Aptos

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

## Gas Optimization

The system is optimized for gas efficiency:

- **Efficient Storage**: Uses Aptos Tables for large datasets
- **Batch Operations**: Supports batch processing where possible
- **View Functions**: Read-only operations don't consume gas
- **Event Optimization**: Minimal event data for gas savings

## Integration

### DeFi Protocols

The system is designed to integrate with existing Aptos DeFi protocols:

- **Fungible Asset Standard**: Uses Aptos Fungible Asset standard
- **Primary Fungible Store**: Integrates with Aptos primary store
- **Object Model**: Leverages Aptos Object model for identity

### External Systems

- **Oracle Integration**: Real-time compliance data
- **KYC Providers**: External identity verification
- **Compliance Services**: Third-party compliance checking
- **Regulatory Reporting**: Automated regulatory reporting

## Deployment

### Mainnet Deployment

1. **Compile Contracts**:
```bash
aptos move compile
```

2. **Deploy Modules**:
```bash
aptos move publish
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
aptos move publish --profile testnet
```

## Monitoring

### Events

Monitor system events for:

- **Identity Events**: Identity creation, updates, freezes
- **Compliance Events**: Compliance check results
- **Transfer Events**: All token transfers
- **Admin Events**: Administrative actions

### Metrics

Key metrics to monitor:

- **Transfer Volume**: Daily/monthly transfer volumes
- **Compliance Rate**: Percentage of compliant transfers
- **Identity Verification**: KYC completion rates
- **System Health**: Module status and performance

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For support and questions:

- **Documentation**: Check the inline documentation in the code
- **Issues**: Open an issue on GitHub
- **Discussions**: Use GitHub Discussions for questions

## Roadmap

### Phase 1: Core Implementation ✅
- [x] Identity system
- [x] Compliance modules
- [x] T-REX token
- [x] DVP/DVE system
- [x] Access control

### Phase 2: Enhanced Features
- [ ] Multi-chain support
- [ ] Advanced compliance rules
- [ ] Automated reporting
- [ ] Integration with external KYC providers

### Phase 3: Enterprise Features
- [ ] White-label solutions
- [ ] Custom compliance modules
- [ ] Advanced analytics
- [ ] Regulatory reporting automation

## Disclaimer

This software is provided for educational and development purposes. Users are responsible for ensuring compliance with applicable laws and regulations. The authors are not responsible for any legal or regulatory issues arising from the use of this software.
