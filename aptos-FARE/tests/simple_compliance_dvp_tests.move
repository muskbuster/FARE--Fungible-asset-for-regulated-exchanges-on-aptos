/// Simple tests for compliance and DVP functionality
/// Tests basic functionality without complex setup

module FARE::simple_compliance_dvp_tests {
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

    // ========== HELPER FUNCTIONS ==========

    fun setup_basic_environment(admin: &signer) {
        // Initialize timestamp
        timestamp::set_time_has_started_for_testing(admin);
        
        // Initialize basic modules
        access_control::initialize(admin);
        onchain_identity::initialize(admin);
        modular_compliance::initialize(admin);
        dvp_manager::initialize(admin);
        trex_token::initialize(admin);
    }

    fun create_test_identity(user: &signer, user_addr: address) {
        account::create_account_for_test(user_addr);
        onchain_identity::create_identity(
            user,
            constants::get_kyc_level_basic(),
            constants::get_investor_type_retail(),
            b"US",
            946684800 // January 1, 2000
        );
    }

    fun create_test_token(admin: &signer): address {
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
        token_address
    }

    // ========== BASIC TESTS ==========

    #[test(admin = @0x1)]
    public fun test_basic_setup(admin: &signer) {
        setup_basic_environment(admin);
        
        // Test that modules are initialized
        assert!(access_control::has_role(@0x1, constants::get_role_token_owner()), 0);
        assert!(access_control::has_role(@0x1, constants::get_role_compliance_officer()), 0);
        assert!(access_control::has_role(@0x1, constants::get_role_token_agent()), 0);
        assert!(access_control::has_role(@0x1, constants::get_role_emergency_pause()), 0);
    }

    #[test(admin = @0x1, user1 = @0x2)]
    public fun test_identity_creation(admin: &signer, user1: &signer) {
        setup_basic_environment(admin);
        
        // Create test identity
        create_test_identity(user1, USER1);
        
        // Verify identity was created
        assert!(onchain_identity::has_identity(USER1), 0);
        
        // Check identity status
        let (has_identity, kyc_level, investor_type, is_frozen, is_recovery_set, is_verified, country_code) = 
            onchain_identity::get_identity_status(USER1);
        
        assert!(has_identity, 0);
        assert!(kyc_level == constants::get_kyc_level_basic(), 0);
        assert!(investor_type == constants::get_investor_type_retail(), 0);
        assert!(!is_frozen, 0);
    }

    #[test(admin = @0x1)]
    public fun test_token_creation(admin: &signer) {
        setup_basic_environment(admin);
        
        // Create test token
        let token_address = create_test_token(admin);
        
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
    public fun test_compliance_initialization(admin: &signer) {
        setup_basic_environment(admin);
        
        // Create test token
        let token_address = create_test_token(admin);
        
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

    #[test(admin = @0x1, user1 = @0x2, user2 = @0x3)]
    public fun test_dvp_order_creation(admin: &signer, user1: &signer, user2: &signer) {
        setup_basic_environment(admin);
        
        // Create test identities
        create_test_identity(user1, USER1);
        create_test_identity(user2, USER2);
        
        // Create test token
        let token_address = create_test_token(admin);
        
        // Create DVP order
        let order_id = dvp_manager::create_dvp_order(
            user1,
            USER2, // buyer
            token_address, // token_address
            100, // token_amount
            1000, // payment_amount
            @0x1, // payment_token_address
            3600 // expiration_time
        );
        
        // Verify order was created
        assert!(dvp_manager::does_dvp_order_exist(order_id), 0);
        assert!(dvp_manager::get_total_dvp_orders() == 1, 0);
        
        // Check order details
        let (seller, buyer, token_addr, token_amt, payment_amt, payment_token, status, created_at, expiration, _) = 
            dvp_manager::get_dvp_order(order_id);
        
        assert!(seller == USER1, 0);
        assert!(buyer == USER2, 0);
        assert!(token_addr == token_address, 0);
        assert!(token_amt == 100, 0);
        assert!(payment_amt == 1000, 0);
        assert!(status == constants::get_dvp_order_status_pending(), 0);
    }

    #[test(admin = @0x1, user1 = @0x2, user2 = @0x3)]
    public fun test_dvp_order_cancellation(admin: &signer, user1: &signer, user2: &signer) {
        setup_basic_environment(admin);
        
        // Create test identities
        create_test_identity(user1, USER1);
        create_test_identity(user2, USER2);
        
        // Create test token
        let token_address = create_test_token(admin);
        
        // Create DVP order
        let order_id = dvp_manager::create_dvp_order(
            user1,
            USER2,
            token_address,
            100,
            1000,
            @0x1,
            3600
        );
        
        // Cancel the order
        dvp_manager::cancel_dvp_order(user1, order_id);
        
        // Verify order was cancelled
        let (_, _, _, _, _, _, status, _, _, _) = dvp_manager::get_dvp_order(order_id);
        assert!(status == constants::get_dvp_order_status_cancelled(), 0);
    }

    #[test(admin = @0x1, user1 = @0x2, user2 = @0x3)]
    public fun test_dvp_order_status_check(admin: &signer, user1: &signer, user2: &signer) {
        setup_basic_environment(admin);
        
        // Create test identities
        create_test_identity(user1, USER1);
        create_test_identity(user2, USER2);
        
        // Create test token
        let token_address = create_test_token(admin);
        
        // Create DVP order
        let order_id = dvp_manager::create_dvp_order(
            user1,
            USER2,
            token_address,
            100,
            1000,
            @0x1,
            3600
        );
        
        // Check order status
        let status = dvp_manager::check_dvp_order_status(order_id);
        assert!(status == constants::get_dvp_order_status_pending(), 0);
        
        // Get user's DVP orders
        let user_orders = dvp_manager::get_user_dvp_orders(USER1);
        assert!(vector::length(&user_orders) == 1, 0);
        assert!(*vector::borrow(&user_orders, 0) == order_id, 0);
    }

    #[test(admin = @0x1)]
    public fun test_compliance_check_functions(admin: &signer) {
        setup_basic_environment(admin);
        
        // Test compliance check functions
        let is_compliant = trex_token::is_compliant_transfer(USER1, USER2, 100);
        // Note: This function currently returns true by default
        assert!(is_compliant, 0);
        
        let restrictions = trex_token::get_transfer_restrictions(USER1);
        // Note: This function currently returns empty vector
        assert!(vector::length(&restrictions) == 0, 0);
    }

    #[test(admin = @0x1)]
    public fun test_token_pause_unpause(admin: &signer) {
        setup_basic_environment(admin);
        
        // Create test token
        let token_address = create_test_token(admin);
        
        // Pause the token
        trex_token::pause_token(admin, token_address, string::utf8(b"Emergency pause"));
        
        // Unpause the token
        trex_token::unpause_token(admin, token_address);
        
        // Test passes if no errors occurred
        assert!(true, 0);
    }
}
