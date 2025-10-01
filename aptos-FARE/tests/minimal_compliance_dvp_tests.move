/// Minimal tests for compliance and DVP functionality
/// Tests basic functionality without complex account setup

module FARE::minimal_compliance_dvp_tests {
    use std::signer;
    use std::string;
    use std::vector;
    use std::timestamp;
    use aptos_framework::account;
    
    use FARE::constants;
    use FARE::access_control;
    use FARE::onchain_identity;
    use FARE::trex_token;
    use FARE::modular_compliance;
    use FARE::dvp_manager;

    // Test accounts
    const ADMIN: address = @0x1;
    const USER1: address = @0x2;
    const USER2: address = @0x3;

    // Test constants
    const TOKEN_NAME: vector<u8> = b"Test Token";
    const TOKEN_SYMBOL: vector<u8> = b"TST";
    const TOKEN_DESCRIPTION: vector<u8> = b"Test T-REX Token";
    const TOKEN_URI: vector<u8> = b"https://example.com/token";
    const INITIAL_SUPPLY: u64 = 1000000;
    const DECIMALS: u8 = 8;

    // ========== BASIC TESTS ==========

    #[test(admin = @0x1)]
    public fun test_constants_functions(admin: &signer) {
        // Test that constants functions work
        let kyc_basic = constants::get_kyc_level_basic();
        let kyc_enhanced = constants::get_kyc_level_enhanced();
        let kyc_verified = constants::get_kyc_level_basic();
        
        assert!(kyc_basic == 1, 0);
        assert!(kyc_enhanced == 2, 0);
        assert!(kyc_verified == 1, 0);
        
        let investor_retail = constants::get_investor_type_retail();
        let investor_accredited = constants::get_investor_type_accredited();
        let investor_institutional = constants::get_investor_type_institutional();
        let investor_professional = constants::get_investor_type_professional();
        
        assert!(investor_retail == 1, 0);
        assert!(investor_accredited == 2, 0);
        assert!(investor_institutional == 3, 0);
        assert!(investor_professional == 4, 0);
        
        let role_token_owner = constants::get_role_token_owner();
        let role_compliance_officer = constants::get_role_compliance_officer();
        let role_token_agent = constants::get_role_token_agent();
        let role_emergency_pause = constants::get_role_emergency_pause();
        
        assert!(role_token_owner == 1, 0);
        assert!(role_compliance_officer == 2, 0);
        assert!(role_token_agent == 3, 0);
        assert!(role_emergency_pause == 5, 0);
        
        let dvp_pending = constants::get_dvp_order_status_pending();
        let dvp_locked = constants::get_dvp_order_status_locked();
        let dvp_executed = constants::get_dvp_order_status_executed();
        let dvp_cancelled = constants::get_dvp_order_status_cancelled();
        let dvp_expired = constants::get_dvp_order_status_expired();
        
        assert!(dvp_pending == 1, 0);
        assert!(dvp_locked == 2, 0);
        assert!(dvp_executed == 3, 0);
        assert!(dvp_cancelled == 4, 0);
        assert!(dvp_expired == 5, 0);
    }

    #[test(admin = @0x1)]
    public fun test_validation_functions(admin: &signer) {
        // Test validation functions
        assert!(constants::is_valid_kyc_level(1), 0);
        assert!(constants::is_valid_kyc_level(2), 0);
        assert!(constants::is_valid_kyc_level(3), 0);
        assert!(constants::is_valid_kyc_level(0), 0);
        assert!(!constants::is_valid_kyc_level(4), 0);
        
        assert!(constants::is_valid_investor_type(1), 0);
        assert!(constants::is_valid_investor_type(2), 0);
        assert!(constants::is_valid_investor_type(3), 0);
        assert!(constants::is_valid_investor_type(4), 0);
        assert!(!constants::is_valid_investor_type(0), 0);
        assert!(!constants::is_valid_investor_type(5), 0);
        
        assert!(constants::is_valid_amount(100), 0);
        assert!(constants::is_valid_amount(1000), 0);
        assert!(!constants::is_valid_amount(0), 0);
    }

    #[test(admin = @0x1)]
    public fun test_access_control_initialization(admin: &signer) {
        // Initialize the account first
        account::create_account_for_test(signer::address_of(admin));
        
        // Initialize timestamp
        timestamp::set_time_has_started_for_testing(admin);
        
        // Initialize access control
        access_control::initialize(admin);
        
        // Verify admin has all roles
        assert!(access_control::has_role(@0x1, constants::get_role_token_owner()), 0);
        assert!(access_control::has_role(@0x1, constants::get_role_compliance_officer()), 0);
        assert!(access_control::has_role(@0x1, constants::get_role_token_agent()), 0);
        assert!(access_control::has_role(@0x1, constants::get_role_emergency_pause()), 0);
    }

    #[test(admin = @0x1)]
    public fun test_identity_initialization(admin: &signer) {
        // Initialize the account first
        account::create_account_for_test(signer::address_of(admin));
        
        // Initialize timestamp
        timestamp::set_time_has_started_for_testing(admin);
        
        // Initialize identity system
        onchain_identity::initialize(admin);
        
        // Test passes if no errors occurred
        assert!(true, 0);
    }

    #[test(admin = @0x1)]
    public fun test_compliance_initialization(admin: &signer) {
        // Initialize the account first
        account::create_account_for_test(signer::address_of(admin));
        
        // Initialize timestamp
        timestamp::set_time_has_started_for_testing(admin);
        
        // Initialize compliance system
        modular_compliance::initialize(admin);
        
        // Test passes if no errors occurred
        assert!(true, 0);
    }

    #[test(admin = @0x1)]
    public fun test_dvp_initialization(admin: &signer) {
        // Initialize the account first
        account::create_account_for_test(signer::address_of(admin));
        
        // Initialize timestamp
        timestamp::set_time_has_started_for_testing(admin);
        
        // Initialize DVP system
        dvp_manager::initialize(admin);
        
        // Test passes if no errors occurred
        assert!(true, 0);
    }

    #[test(admin = @0x1)]
    public fun test_trex_token_initialization(admin: &signer) {
        // Initialize the account first
        account::create_account_for_test(signer::address_of(admin));
        
        // Initialize timestamp
        timestamp::set_time_has_started_for_testing(admin);
        
        // Initialize T-REX token system
        trex_token::initialize(admin);
        
        // Test passes if no errors occurred
        assert!(true, 0);
    }

    #[test(admin = @0x1)]
    public fun test_token_creation(admin: &signer) {
        // Initialize the account first
        account::create_account_for_test(signer::address_of(admin));
        
        // Initialize timestamp
        timestamp::set_time_has_started_for_testing(admin);
        
        // Initialize all systems
        access_control::initialize(admin);
        onchain_identity::initialize(admin);
        modular_compliance::initialize(admin);
        dvp_manager::initialize(admin);
        trex_token::initialize(admin);
        
        // Create test token
        let (token_address, _metadata) = trex_token::create_trex_token(
            admin,
            string::utf8(TOKEN_NAME),
            string::utf8(TOKEN_SYMBOL),
            DECIMALS,
            string::utf8(TOKEN_DESCRIPTION),
            string::utf8(TOKEN_URI),
            string::utf8(TOKEN_URI),
            INITIAL_SUPPLY,
            true, // supply_cap_enabled
            true, // compliance_enabled
            true, // identity_verification_required
            constants::get_kyc_level_basic(),
            constants::get_investor_type_retail(),
            true, // country_restrictions_enabled
            true, // transfer_restrictions_enabled
            true  // balance_restrictions_enabled
        );
        
        // Verify token was created
        assert!(trex_token::is_trex_compliant(token_address), 0);
        
        // Check token configuration
        let (compliance_enabled, identity_verification_required, required_kyc_level, required_investor_type, 
             country_restrictions_enabled, transfer_restrictions_enabled, balance_restrictions_enabled, 
             created_at, updated_at) = trex_token::get_trex_token_config(token_address);
        
        assert!(compliance_enabled, 0);
        assert!(identity_verification_required, 0);
        assert!(required_kyc_level == constants::get_kyc_level_basic(), 0);
        assert!(required_investor_type == constants::get_investor_type_retail(), 0);
        assert!(country_restrictions_enabled, 0);
        assert!(transfer_restrictions_enabled, 0);
        assert!(balance_restrictions_enabled, 0);
    }

    #[test(admin = @0x1)]
    public fun test_compliance_functions(admin: &signer) {
        // Initialize the account first
        account::create_account_for_test(signer::address_of(admin));
        
        // Initialize timestamp
        timestamp::set_time_has_started_for_testing(admin);
        
        // Initialize all systems
        access_control::initialize(admin);
        onchain_identity::initialize(admin);
        modular_compliance::initialize(admin);
        dvp_manager::initialize(admin);
        trex_token::initialize(admin);
        
        // Create test token
        let (token_address, _metadata) = trex_token::create_trex_token(
            admin,
            string::utf8(TOKEN_NAME),
            string::utf8(TOKEN_SYMBOL),
            DECIMALS,
            string::utf8(TOKEN_DESCRIPTION),
            string::utf8(TOKEN_URI),
            string::utf8(TOKEN_URI),
            INITIAL_SUPPLY,
            true, // supply_cap_enabled
            true, // compliance_enabled
            true, // identity_verification_required
            constants::get_kyc_level_basic(),
            constants::get_investor_type_retail(),
            true, // country_restrictions_enabled
            true, // transfer_restrictions_enabled
            true  // balance_restrictions_enabled
        );
        
        // Initialize token compliance
        modular_compliance::initialize_token_compliance(admin, token_address);
        
        // Verify compliance was initialized
        assert!(modular_compliance::has_token_compliance_config(token_address), 0);
        
        // Check compliance configuration
        let (enabled_modules, total_modules, last_updated) = 
            modular_compliance::get_token_compliance_config(token_address);
        
        assert!(vector::length(&enabled_modules) == 0, 0); // No modules enabled by default
        assert!(total_modules == 0, 0);
    }

    #[test(admin = @0x1)]
    public fun test_token_pause_unpause(admin: &signer) {
        // Initialize the account first
        account::create_account_for_test(signer::address_of(admin));
        
        // Initialize timestamp
        timestamp::set_time_has_started_for_testing(admin);
        
        // Initialize all systems
        access_control::initialize(admin);
        onchain_identity::initialize(admin);
        modular_compliance::initialize(admin);
        dvp_manager::initialize(admin);
        trex_token::initialize(admin);
        
        // Create test token
        let (token_address, _metadata) = trex_token::create_trex_token(
            admin,
            string::utf8(TOKEN_NAME),
            string::utf8(TOKEN_SYMBOL),
            DECIMALS,
            string::utf8(TOKEN_DESCRIPTION),
            string::utf8(TOKEN_URI),
            string::utf8(TOKEN_URI),
            INITIAL_SUPPLY,
            true, // supply_cap_enabled
            true, // compliance_enabled
            true, // identity_verification_required
            constants::get_kyc_level_basic(),
            constants::get_investor_type_retail(),
            true, // country_restrictions_enabled
            true, // transfer_restrictions_enabled
            true  // balance_restrictions_enabled
        );
        
        // Pause the token
        trex_token::pause_token(admin, token_address, string::utf8(b"Emergency pause"));
        
        // Unpause the token
        trex_token::unpause_token(admin, token_address);
        
        // Test passes if no errors occurred
        assert!(true, 0);
    }
}
