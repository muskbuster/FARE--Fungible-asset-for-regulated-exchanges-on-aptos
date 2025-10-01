/// Constants module for T-REX compliant token system
/// Defines all error codes, claim topics, and system constants

module FARE::constants {
    use std::error;
    use std::signer;
    use std::timestamp;

    // ========== ERROR CODES ==========
    
    /// Identity related errors (1000-1999)
    const EIDENTITY_NOT_FOUND: u64 = 1001;
    const EIDENTITY_ALREADY_EXISTS: u64 = 1002;
    const EIDENTITY_FROZEN: u64 = 1003;
    const EIDENTITY_INVALID: u64 = 1004;
    const EIDENTITY_RECOVERY_NOT_AUTHORIZED: u64 = 1005;
    const EIDENTITY_CLAIM_EXPIRED: u64 = 1006;
    const EIDENTITY_CLAIM_INVALID: u64 = 1007;
    const EIDENTITY_CLAIM_ALREADY_EXISTS: u64 = 1008;
    const EIDENTITY_CLAIM_NOT_FOUND: u64 = 1009;
    const EIDENTITY_CLAIM_ISSUER_NOT_AUTHORIZED: u64 = 1010;

    /// Compliance related errors (2000-2999)
    const ECOMPLIANCE_MODULE_NOT_FOUND: u64 = 2001;
    const ECOMPLIANCE_MODULE_ALREADY_EXISTS: u64 = 2002;
    const ECOMPLIANCE_CHECK_FAILED: u64 = 2003;
    const ECOMPLIANCE_TRANSFER_RESTRICTED: u64 = 2004;
    const ECOMPLIANCE_COUNTRY_BLOCKED: u64 = 2005;
    const ECOMPLIANCE_BALANCE_LIMIT_EXCEEDED: u64 = 2006;
    const ECOMPLIANCE_DAILY_LIMIT_EXCEEDED: u64 = 2007;
    const ECOMPLIANCE_INVESTOR_TYPE_RESTRICTED: u64 = 2008;
    const ECOMPLIANCE_AGE_RESTRICTION: u64 = 2009;
    const ECOMPLIANCE_PEP_RESTRICTION: u64 = 2010;
    const ECOMPLIANCE_WHITELIST_REQUIRED: u64 = 2011;
    const ECOMPLIANCE_BLACKLISTED: u64 = 2012;
    const ECOMPLIANCE_TRADING_HOURS: u64 = 2013;
    const ECOMPLIANCE_TRANSFER_LOCK: u64 = 2014;

    /// Token related errors (3000-3999)
    const ETOKEN_PAUSED: u64 = 3001;
    const ETOKEN_SUPPLY_CAP_EXCEEDED: u64 = 3002;
    const ETOKEN_FORCED_TRANSFER_NOT_AUTHORIZED: u64 = 3003;
    const ETOKEN_ROLE_NOT_AUTHORIZED: u64 = 3004;
    const ETOKEN_ACCOUNT_FROZEN: u64 = 3005;
    const ETOKEN_ACCOUNT_PARTIALLY_FROZEN: u64 = 3006;
    const ETOKEN_RECOVERY_NOT_AUTHORIZED: u64 = 3007;
    const ETOKEN_METADATA_INVALID: u64 = 3008;

    /// DVP/DVE related errors (4000-4999)
    const EDVP_ORDER_NOT_FOUND: u64 = 4001;
    const EDVP_ORDER_ALREADY_EXISTS: u64 = 4002;
    const EDVP_ORDER_EXPIRED: u64 = 4003;
    const EDVP_ORDER_CANCELLED: u64 = 4004;
    const EDVP_ORDER_ALREADY_EXECUTED: u64 = 4005;
    const EDVP_ORDER_INSUFFICIENT_BALANCE: u64 = 4006;
    const EDVP_ORDER_INVALID_AMOUNT: u64 = 4007;
    const EDVP_ORDER_COMPLIANCE_FAILED: u64 = 4008;
    const EDVP_ESCROW_NOT_FOUND: u64 = 4009;
    const EDVP_ESCROW_ALREADY_EXISTS: u64 = 4010;
    const EDVP_SETTLEMENT_FAILED: u64 = 4011;
    const EDVP_EXCHANGE_NOT_REGISTERED: u64 = 4012;
    const EDVP_EXCHANGE_COMPLIANCE_LEVEL_INSUFFICIENT: u64 = 4013;

    /// Access control errors (5000-5999)
    const EACCESS_CONTROL_ROLE_NOT_FOUND: u64 = 5001;
    const EACCESS_CONTROL_ROLE_ALREADY_EXISTS: u64 = 5002;
    const EACCESS_CONTROL_NOT_AUTHORIZED: u64 = 5003;
    const EACCESS_CONTROL_ROLE_TRANSFER_DELAY: u64 = 5004;
    const EACCESS_CONTROL_MULTISIG_REQUIRED: u64 = 5005;
    const EACCESS_CONTROL_EMERGENCY_PAUSE_NOT_AUTHORIZED: u64 = 5006;

    /// General errors (6000-6999)
    const EINVALID_PARAMETER: u64 = 6001;
    const EINSUFFICIENT_BALANCE: u64 = 6002;
    const EOVERFLOW: u64 = 6003;
    const EUNDERFLOW: u64 = 6004;
    const EINVALID_SIGNATURE: u64 = 6005;
    const EINVALID_TIMESTAMP: u64 = 6006;
    const EINVALID_ADDRESS: u64 = 6007;
    const EINVALID_AMOUNT: u64 = 6008;
    const EINVALID_DURATION: u64 = 6009;
    const EINVALID_COUNTRY_CODE: u64 = 6010;
    const EINSUFFICIENT_KYC_LEVEL: u64 = 6011;
    const EINSUFFICIENT_INVESTOR_TYPE: u64 = 6012;

    // ========== CLAIM TOPICS (ERC-735 Standard) ==========
    
    /// KYC (Know Your Customer) verification
    const CLAIM_TOPIC_KYC: u256 = 1;
    
    /// AML (Anti-Money Laundering) verification
    const CLAIM_TOPIC_AML: u256 = 2;
    
    /// Country of residence
    const CLAIM_TOPIC_COUNTRY: u256 = 3;
    
    /// Investor accreditation status
    const CLAIM_TOPIC_ACCREDITATION: u256 = 4;
    
    /// Age verification
    const CLAIM_TOPIC_AGE: u256 = 5;
    
    /// Balance limit for transfers
    const CLAIM_TOPIC_BALANCE_LIMIT: u256 = 6;
    
    /// PEP (Politically Exposed Person) status
    const CLAIM_TOPIC_PEP: u256 = 7;
    
    /// Sanctions screening status
    const CLAIM_TOPIC_SANCTIONS: u256 = 8;
    
    /// Tax residency information
    const CLAIM_TOPIC_TAX_RESIDENCY: u256 = 9;
    
    /// Source of funds verification
    const CLAIM_TOPIC_SOURCE_OF_FUNDS: u256 = 10;

    // ========== KYC LEVELS ==========
    
    /// No KYC verification
    const KYC_LEVEL_NONE: u8 = 0;
    
    /// Basic KYC (identity verification)
    const KYC_LEVEL_BASIC: u8 = 1;
    
    /// Enhanced KYC (identity + address verification)
    const KYC_LEVEL_ENHANCED: u8 = 2;
    
    /// Full KYC (identity + address + source of funds)
    const KYC_LEVEL_FULL: u8 = 3;

    // ========== INVESTOR TYPES ==========
    
    /// Retail investor
    const INVESTOR_TYPE_RETAIL: u8 = 1;
    
    /// Accredited investor
    const INVESTOR_TYPE_ACCREDITED: u8 = 2;
    
    /// Institutional investor
    const INVESTOR_TYPE_INSTITUTIONAL: u8 = 3;
    
    /// Professional investor
    const INVESTOR_TYPE_PROFESSIONAL: u8 = 4;

    // ========== COMPLIANCE MODULE TYPES ==========
    
    /// Transfer restrictions module
    const COMPLIANCE_MODULE_TRANSFER_RESTRICTIONS: u8 = 1;
    
    /// Balance restrictions module
    const COMPLIANCE_MODULE_BALANCE_RESTRICTIONS: u8 = 2;
    
    /// Country restrictions module
    const COMPLIANCE_MODULE_COUNTRY_RESTRICTIONS: u8 = 3;
    
    /// Investor type restrictions module
    const COMPLIANCE_MODULE_INVESTOR_TYPE_RESTRICTIONS: u8 = 4;
    
    /// Whitelist/blacklist module
    const COMPLIANCE_MODULE_WHITELIST_BLACKLIST: u8 = 5;
    
    /// Time-based restrictions module
    const COMPLIANCE_MODULE_TIME_BASED_RESTRICTIONS: u8 = 6;

    // ========== DVP ORDER STATUS ==========
    
    /// Order is pending and can be executed
    const DVP_ORDER_STATUS_PENDING: u8 = 1;
    
    /// Order is locked (funds escrowed)
    const DVP_ORDER_STATUS_LOCKED: u8 = 2;
    
    /// Order has been executed successfully
    const DVP_ORDER_STATUS_EXECUTED: u8 = 3;
    
    /// Order has been cancelled
    const DVP_ORDER_STATUS_CANCELLED: u8 = 4;
    
    /// Order has expired
    const DVP_ORDER_STATUS_EXPIRED: u8 = 5;

    // ========== EXCHANGE COMPLIANCE LEVELS ==========
    
    /// Basic compliance level
    const EXCHANGE_COMPLIANCE_BASIC: u8 = 1;
    
    /// Enhanced compliance level
    const EXCHANGE_COMPLIANCE_ENHANCED: u8 = 2;
    
    /// Full compliance level
    const EXCHANGE_COMPLIANCE_FULL: u8 = 3;

    // ========== ROLE TYPES ==========
    
    /// Token owner role
    const ROLE_TOKEN_OWNER: u8 = 1;
    
    /// Compliance officer role
    const ROLE_COMPLIANCE_OFFICER: u8 = 2;
    
    /// Token agent role
    const ROLE_TOKEN_AGENT: u8 = 3;
    
    /// Claim issuer role
    const ROLE_CLAIM_ISSUER: u8 = 4;
    
    /// Emergency pause role
    const ROLE_EMERGENCY_PAUSE: u8 = 5;

    // ========== TIME CONSTANTS ==========
    
    /// Default role transfer delay (24 hours)
    const DEFAULT_ROLE_TRANSFER_DELAY: u64 = 86400;
    
    /// Default claim expiration (1 year)
    const DEFAULT_CLAIM_EXPIRATION: u64 = 31536000;
    
    /// Default DVP order expiration (7 days)
    const DEFAULT_DVP_ORDER_EXPIRATION: u64 = 604800;
    
    /// Default trading hours start (9 AM UTC)
    const DEFAULT_TRADING_HOURS_START: u64 = 32400;
    
    /// Default trading hours end (5 PM UTC)
    const DEFAULT_TRADING_HOURS_END: u64 = 61200;

    // ========== LIMIT CONSTANTS ==========
    
    /// Maximum number of compliance modules per token
    const MAX_COMPLIANCE_MODULES: u64 = 20;
    
    /// Maximum number of claims per identity
    const MAX_CLAIMS_PER_IDENTITY: u64 = 100;
    
    /// Maximum number of DVP orders per user
    const MAX_DVP_ORDERS_PER_USER: u64 = 50;
    
    /// Maximum transfer amount (in smallest unit)
    const MAX_TRANSFER_AMOUNT: u64 = 1000000000000000000; // 1 token with 18 decimals
    
    /// Maximum daily transfer volume (in smallest unit)
    const MAX_DAILY_TRANSFER_VOLUME: u64 = 10000000000000000000; // 10 tokens with 18 decimals

    // ========== VIEW FUNCTIONS ==========
    
    /// Get error code for identity not found
    public fun get_identity_not_found_error(): u64 {
        EIDENTITY_NOT_FOUND
    }
    
    /// Get error code for identity already exists
    public fun get_identity_already_exists_error(): u64 {
        EIDENTITY_ALREADY_EXISTS
    }
    
    /// Get error code for identity frozen
    public fun get_identity_frozen_error(): u64 {
        EIDENTITY_FROZEN
    }
    
    /// Get error code for compliance check failed
    public fun get_compliance_check_failed_error(): u64 {
        ECOMPLIANCE_CHECK_FAILED
    }
    
    /// Get error code for transfer restricted
    public fun get_compliance_transfer_restricted_error(): u64 {
        ECOMPLIANCE_TRANSFER_RESTRICTED
    }
    
    /// Get error code for token paused
    public fun get_token_paused_error(): u64 {
        ETOKEN_PAUSED
    }
    
    /// Get error code for DVP order not found
    public fun get_dvp_order_not_found_error(): u64 {
        EDVP_ORDER_NOT_FOUND
    }
    
    /// Get error code for access control not authorized
    public fun get_access_control_not_authorized_error(): u64 {
        EACCESS_CONTROL_NOT_AUTHORIZED
    }
    
    /// Get error code for invalid parameter
    public fun get_invalid_parameter_error(): u64 {
        EINVALID_PARAMETER
    }
    
    /// Get error code for insufficient balance
    public fun get_insufficient_balance_error(): u64 {
        EINSUFFICIENT_BALANCE
    }
    
    /// Get error code for insufficient KYC level
    public fun get_insufficient_kyc_level_error(): u64 {
        EINSUFFICIENT_KYC_LEVEL
    }
    
    /// Get error code for insufficient investor type
    public fun get_insufficient_investor_type_error(): u64 {
        EINSUFFICIENT_INVESTOR_TYPE
    }

    // ========== ADDITIONAL ERROR GETTERS ==========
    
    /// Get error code for identity claim already exists
    public fun get_identity_claim_already_exists_error(): u64 {
        EIDENTITY_CLAIM_ALREADY_EXISTS
    }
    
    /// Get error code for identity claim invalid
    public fun get_identity_claim_invalid_error(): u64 {
        EIDENTITY_CLAIM_INVALID
    }
    
    /// Get error code for identity claim not found
    public fun get_identity_claim_not_found_error(): u64 {
        EIDENTITY_CLAIM_NOT_FOUND
    }
    
    /// Get error code for identity claim expired
    public fun get_identity_claim_expired_error(): u64 {
        EIDENTITY_CLAIM_EXPIRED
    }
    
    /// Get error code for identity claim issuer not authorized
    public fun get_identity_claim_issuer_not_authorized_error(): u64 {
        EIDENTITY_CLAIM_ISSUER_NOT_AUTHORIZED
    }
    
    /// Get error code for identity recovery not authorized
    public fun get_identity_recovery_not_authorized_error(): u64 {
        EIDENTITY_RECOVERY_NOT_AUTHORIZED
    }
    
    /// Get error code for compliance module not found
    public fun get_compliance_module_not_found_error(): u64 {
        ECOMPLIANCE_MODULE_NOT_FOUND
    }
    
    /// Get error code for compliance module already exists
    public fun get_compliance_module_already_exists_error(): u64 {
        ECOMPLIANCE_MODULE_ALREADY_EXISTS
    }
    
    /// Get error code for token supply cap exceeded
    public fun get_token_supply_cap_exceeded_error(): u64 {
        ETOKEN_SUPPLY_CAP_EXCEEDED
    }
    
    /// Get error code for token account frozen
    public fun get_token_account_frozen_error(): u64 {
        ETOKEN_ACCOUNT_FROZEN
    }
    
    /// Get error code for token forced transfer not authorized
    public fun get_token_forced_transfer_not_authorized_error(): u64 {
        ETOKEN_FORCED_TRANSFER_NOT_AUTHORIZED
    }
    
    /// Get error code for token recovery not authorized
    public fun get_token_recovery_not_authorized_error(): u64 {
        ETOKEN_RECOVERY_NOT_AUTHORIZED
    }
    
    /// Get error code for DVP order already executed
    public fun get_dvp_order_already_executed_error(): u64 {
        EDVP_ORDER_ALREADY_EXECUTED
    }
    
    /// Get error code for DVP order expired
    public fun get_dvp_order_expired_error(): u64 {
        EDVP_ORDER_EXPIRED
    }
    
    /// Get error code for DVP escrow not found
    public fun get_dvp_escrow_not_found_error(): u64 {
        EDVP_ESCROW_NOT_FOUND
    }
    
    /// Get error code for DVP settlement failed
    public fun get_dvp_settlement_failed_error(): u64 {
        EDVP_SETTLEMENT_FAILED
    }
    
    /// Get error code for DVP exchange not registered
    public fun get_dvp_exchange_not_registered_error(): u64 {
        EDVP_EXCHANGE_NOT_REGISTERED
    }
    
    /// Get error code for invalid country code
    public fun get_invalid_country_code_error(): u64 {
        EINVALID_COUNTRY_CODE
    }
    
    /// Get error code for invalid amount
    public fun get_invalid_amount_error(): u64 {
        EINVALID_AMOUNT
    }
    
    /// Get error code for compliance country blocked
    public fun get_compliance_country_blocked_error(): u64 {
        ECOMPLIANCE_COUNTRY_BLOCKED
    }
    
    /// Get error code for compliance trading hours
    public fun get_compliance_trading_hours_error(): u64 {
        ECOMPLIANCE_TRADING_HOURS
    }
    
    /// Get error code for compliance transfer lock
    public fun get_compliance_transfer_lock_error(): u64 {
        ECOMPLIANCE_TRANSFER_LOCK
    }
    
    /// Get error code for compliance daily limit exceeded
    public fun get_compliance_daily_limit_exceeded_error(): u64 {
        ECOMPLIANCE_DAILY_LIMIT_EXCEEDED
    }
    
    /// Get exchange compliance basic level
    public fun get_exchange_compliance_basic(): u8 {
        EXCHANGE_COMPLIANCE_BASIC
    }
    
    /// Get exchange compliance full level
    public fun get_exchange_compliance_full(): u8 {
        EXCHANGE_COMPLIANCE_FULL
    }

    // ========== CLAIM TOPIC GETTERS ==========
    
    /// Get KYC claim topic
    public fun get_kyc_claim_topic(): u256 {
        CLAIM_TOPIC_KYC
    }
    
    /// Get AML claim topic
    public fun get_aml_claim_topic(): u256 {
        CLAIM_TOPIC_AML
    }
    
    /// Get country claim topic
    public fun get_country_claim_topic(): u256 {
        CLAIM_TOPIC_COUNTRY
    }
    
    /// Get accreditation claim topic
    public fun get_accreditation_claim_topic(): u256 {
        CLAIM_TOPIC_ACCREDITATION
    }
    
    /// Get age claim topic
    public fun get_age_claim_topic(): u256 {
        CLAIM_TOPIC_AGE
    }
    
    /// Get balance limit claim topic
    public fun get_balance_limit_claim_topic(): u256 {
        CLAIM_TOPIC_BALANCE_LIMIT
    }
    
    /// Get PEP claim topic
    public fun get_pep_claim_topic(): u256 {
        CLAIM_TOPIC_PEP
    }
    
    /// Get sanctions claim topic
    public fun get_sanctions_claim_topic(): u256 {
        CLAIM_TOPIC_SANCTIONS
    }

    // ========== KYC LEVEL GETTERS ==========
    
    /// Get KYC level none
    public fun get_kyc_level_none(): u8 {
        KYC_LEVEL_NONE
    }
    
    /// Get KYC level basic
    public fun get_kyc_level_basic(): u8 {
        KYC_LEVEL_BASIC
    }
    
    /// Get KYC level enhanced
    public fun get_kyc_level_enhanced(): u8 {
        KYC_LEVEL_ENHANCED
    }
    
    /// Get KYC level full
    public fun get_kyc_level_full(): u8 {
        KYC_LEVEL_FULL
    }

    // ========== INVESTOR TYPE GETTERS ==========
    
    /// Get retail investor type
    public fun get_investor_type_retail(): u8 {
        INVESTOR_TYPE_RETAIL
    }
    
    /// Get accredited investor type
    public fun get_investor_type_accredited(): u8 {
        INVESTOR_TYPE_ACCREDITED
    }
    
    /// Get institutional investor type
    public fun get_investor_type_institutional(): u8 {
        INVESTOR_TYPE_INSTITUTIONAL
    }
    
    /// Get professional investor type
    public fun get_investor_type_professional(): u8 {
        INVESTOR_TYPE_PROFESSIONAL
    }

    // ========== COMPLIANCE MODULE TYPE GETTERS ==========
    
    /// Get transfer restrictions module type
    public fun get_compliance_module_transfer_restrictions(): u8 {
        COMPLIANCE_MODULE_TRANSFER_RESTRICTIONS
    }
    
    /// Get balance restrictions module type
    public fun get_compliance_module_balance_restrictions(): u8 {
        COMPLIANCE_MODULE_BALANCE_RESTRICTIONS
    }
    
    /// Get country restrictions module type
    public fun get_compliance_module_country_restrictions(): u8 {
        COMPLIANCE_MODULE_COUNTRY_RESTRICTIONS
    }
    
    /// Get investor type restrictions module type
    public fun get_compliance_module_investor_type_restrictions(): u8 {
        COMPLIANCE_MODULE_INVESTOR_TYPE_RESTRICTIONS
    }
    
    /// Get whitelist/blacklist module type
    public fun get_compliance_module_whitelist_blacklist(): u8 {
        COMPLIANCE_MODULE_WHITELIST_BLACKLIST
    }
    
    /// Get time-based restrictions module type
    public fun get_compliance_module_time_based_restrictions(): u8 {
        COMPLIANCE_MODULE_TIME_BASED_RESTRICTIONS
    }

    // ========== DVP ORDER STATUS GETTERS ==========
    
    /// Get DVP order status pending
    public fun get_dvp_order_status_pending(): u8 {
        DVP_ORDER_STATUS_PENDING
    }
    
    /// Get DVP order status locked
    public fun get_dvp_order_status_locked(): u8 {
        DVP_ORDER_STATUS_LOCKED
    }
    
    /// Get DVP order status executed
    public fun get_dvp_order_status_executed(): u8 {
        DVP_ORDER_STATUS_EXECUTED
    }
    
    /// Get DVP order status cancelled
    public fun get_dvp_order_status_cancelled(): u8 {
        DVP_ORDER_STATUS_CANCELLED
    }
    
    /// Get DVP order status expired
    public fun get_dvp_order_status_expired(): u8 {
        DVP_ORDER_STATUS_EXPIRED
    }

    // ========== ROLE TYPE GETTERS ==========
    
    /// Get token owner role
    public fun get_role_token_owner(): u8 {
        ROLE_TOKEN_OWNER
    }
    
    /// Get compliance officer role
    public fun get_role_compliance_officer(): u8 {
        ROLE_COMPLIANCE_OFFICER
    }
    
    /// Get token agent role
    public fun get_role_token_agent(): u8 {
        ROLE_TOKEN_AGENT
    }
    
    /// Get claim issuer role
    public fun get_role_claim_issuer(): u8 {
        ROLE_CLAIM_ISSUER
    }
    
    /// Get emergency pause role
    public fun get_role_emergency_pause(): u8 {
        ROLE_EMERGENCY_PAUSE
    }

    // ========== TIME CONSTANT GETTERS ==========
    
    /// Get default role transfer delay
    public fun get_default_role_transfer_delay(): u64 {
        DEFAULT_ROLE_TRANSFER_DELAY
    }
    
    /// Get default claim expiration
    public fun get_default_claim_expiration(): u64 {
        DEFAULT_CLAIM_EXPIRATION
    }
    
    /// Get default DVP order expiration
    public fun get_default_dvp_order_expiration(): u64 {
        DEFAULT_DVP_ORDER_EXPIRATION
    }
    
    /// Get default trading hours start
    public fun get_default_trading_hours_start(): u64 {
        DEFAULT_TRADING_HOURS_START
    }
    
    /// Get default trading hours end
    public fun get_default_trading_hours_end(): u64 {
        DEFAULT_TRADING_HOURS_END
    }

    // ========== LIMIT CONSTANT GETTERS ==========
    
    /// Get maximum compliance modules
    public fun get_max_compliance_modules(): u64 {
        MAX_COMPLIANCE_MODULES
    }
    
    /// Get maximum claims per identity
    public fun get_max_claims_per_identity(): u64 {
        MAX_CLAIMS_PER_IDENTITY
    }
    
    /// Get maximum DVP orders per user
    public fun get_max_dvp_orders_per_user(): u64 {
        MAX_DVP_ORDERS_PER_USER
    }
    
    /// Get maximum transfer amount
    public fun get_max_transfer_amount(): u64 {
        MAX_TRANSFER_AMOUNT
    }
    
    /// Get maximum daily transfer volume
    public fun get_max_daily_transfer_volume(): u64 {
        MAX_DAILY_TRANSFER_VOLUME
    }

    // ========== VALIDATION FUNCTIONS ==========
    
    /// Check if KYC level is valid
    public fun is_valid_kyc_level(kyc_level: u8): bool {
        kyc_level <= KYC_LEVEL_FULL
    }
    
    /// Check if investor type is valid
    public fun is_valid_investor_type(investor_type: u8): bool {
        investor_type >= INVESTOR_TYPE_RETAIL && investor_type <= INVESTOR_TYPE_PROFESSIONAL
    }
    
    /// Check if compliance module type is valid
    public fun is_valid_compliance_module_type(module_type: u8): bool {
        module_type >= COMPLIANCE_MODULE_TRANSFER_RESTRICTIONS && 
        module_type <= COMPLIANCE_MODULE_TIME_BASED_RESTRICTIONS
    }
    
    /// Check if DVP order status is valid
    public fun is_valid_dvp_order_status(status: u8): bool {
        status >= DVP_ORDER_STATUS_PENDING && status <= DVP_ORDER_STATUS_EXPIRED
    }
    
    /// Check if role type is valid
    public fun is_valid_role_type(role_type: u8): bool {
        role_type >= ROLE_TOKEN_OWNER && role_type <= ROLE_EMERGENCY_PAUSE
    }
    
    /// Check if country code is valid (basic validation)
    public fun is_valid_country_code(country_code: vector<u8>): bool {
        std::string::length(&std::string::utf8(country_code)) == 2
    }
    
    /// Check if amount is within valid range
    public fun is_valid_amount(amount: u64): bool {
        amount > 0 && amount <= MAX_TRANSFER_AMOUNT
    }
    
    /// Check if timestamp is valid (not in the past)
    public fun is_valid_timestamp(timestamp: u64): bool {
        timestamp > 0
    }
    
    /// Check if duration is valid
    public fun is_valid_duration(duration: u64): bool {
        duration > 0
    }
}
