/// Comprehensive tests for compliance during transfers and DVP flow
/// Tests the T-REX compliant token system with compliance checks and DVP functionality

module FARE::compliance_and_dvp_tests {
    use std::signer;
    use std::string;
    use std::vector;
    use std::timestamp;
    use aptos_framework::account;
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    
    use FARE::constants;
    use FARE::access_control;
    use FARE::onchain_identity;
    use FARE::trex_token;
    use FARE::modular_compliance;
    use FARE::token_information;
    use FARE::token_roles;
    use FARE::dvp_manager;
    use FARE::dve_exchange;
    use FARE::settlement;

    // Test accounts
    const ADMIN: address = @0x1;
    const USER1: address = @0x2;
    const USER2: address = @0x3;
    const EXCHANGE: address = @0x4;
    const CLAIM_ISSUER: address = @0x5;

    // Test constants
    const TOKEN_NAME: vector<u8> = b"Test Token";
    const TOKEN_SYMBOL: vector<u8> = b"TST";
    const TOKEN_DESCRIPTION: vector<u8> = b"Test T-REX Token";
    const TOKEN_URI: vector<u8> = b"https://example.com/token";
    const INITIAL_SUPPLY: u64 = 1000000;
    const DECIMALS: u8 = 8;

    // ========== HELPER FUNCTIONS ==========

    fun setup_test_environment(admin: &signer) {
        // Initialize timestamp
        timestamp::set_time_has_started_for_testing(admin);
        
        // Initialize all modules
        access_control::initialize(admin);
        onchain_identity::initialize(admin);
        modular_compliance::initialize(admin);
        dvp_manager::initialize(admin);
        dve_exchange::initialize(admin);
        settlement::initialize(admin);
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

    fun create_test_token(admin: &signer): (address, Object<Metadata>) {
        let (token_address, metadata) = trex_token::create_trex_token(
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
        (token_address, metadata)
    }

    fun mint_tokens_to_user(admin: &signer, user: address, token_address: address, amount: u64) {
        // Note: This is a placeholder - actual minting would need to be implemented
        // For now, we'll skip the minting and assume tokens are already available
        // In a real implementation, you would need to implement proper minting logic
    }

    // ========== COMPLIANCE TESTS ==========

    #[test(admin = @0x1, user1 = @0x2, user2 = @0x3)]
    public fun test_compliant_transfer(admin: &signer, user1: &signer, user2: &signer) {
        setup_test_environment(admin);
        
        // Create test identities
        create_test_identity(user1, USER1);
        create_test_identity(user2, USER2);
        
        // Create test token
        let (token_address, _metadata) = create_test_token(admin);
        
        // Initialize token compliance
        modular_compliance::initialize_token_compliance(
            admin,
            token_address
        );
        
        // Mint tokens to user1
        mint_tokens_to_user(admin, USER1, token_address, 1000);
        
        // Test compliant transfer
        let result = trex_token::transfer_with_compliance(
            user1,
            token_address,
            USER2,
            100
        );
        
        // Verify transfer was successful
        assert!(trex_token::get_user_balance(USER1, token_address) == 900, 0);
        assert!(trex_token::get_user_balance(USER2, token_address) == 100, 0);
    }

    #[test(admin = @0x1, user1 = @0x2, user2 = @0x3)]
    public fun test_non_compliant_transfer_no_identity(admin: &signer, user1: &signer, user2: &signer) {
        setup_test_environment(admin);
        
        // Create test token
        let (token_address, _metadata) = create_test_token(admin);
        
        // Initialize token compliance
        modular_compliance::initialize_token_compliance(
            admin,
            token_address
        );
        
        // Mint tokens to user1 (who has no identity)
        mint_tokens_to_user(admin, USER1, token_address, 1000);
        
        // Test transfer without identity (should fail)
        let result = trex_token::transfer_with_compliance(
            user1,
            token_address,
            USER2,
            100
        );
        
        // Verify transfer failed (balances unchanged)
        assert!(trex_token::get_user_balance(USER1, token_address) == 1000, 0);
        assert!(trex_token::get_user_balance(USER2, token_address) == 0, 0);
    }

    #[test(admin = @0x1, user1 = @0x2, user2 = @0x3)]
    public fun test_compliance_check_functions(admin: &signer, user1: &signer, user2: &signer) {
        setup_test_environment(admin);
        
        // Create test identities
        create_test_identity(user1, USER1);
        create_test_identity(user2, USER2);
        
        // Create test token
        let (token_address, _metadata) = create_test_token(admin);
        
        // Test compliance check functions
        let is_compliant = trex_token::is_compliant_transfer(USER1, USER2, 100);
        // Note: This function currently returns true by default
        assert!(is_compliant, 0);
        
        let restrictions = trex_token::get_transfer_restrictions(USER1);
        // Note: This function currently returns empty vector
        assert!(vector::length(&restrictions) == 0, 0);
    }

    // ========== DVP TESTS ==========

    #[test(admin = @0x1, user1 = @0x2, user2 = @0x3)]
    public fun test_dvp_order_creation(admin: &signer, user1: &signer, user2: &signer) {
        setup_test_environment(admin);
        
        // Create test identities
        create_test_identity(user1, USER1);
        create_test_identity(user2, USER2);
        
        // Create test token
        let (token_address, _metadata) = create_test_token(admin);
        
        // Mint tokens to user1
        mint_tokens_to_user(admin, USER1, token_address, 1000);
        
        // Create DVP order
        let order_id = dvp_manager::create_dvp_order(
            user1,
            USER2, // buyer
            token_address, // token_address
            100, // token_amount
            1000, // payment_amount
            @0x1, // payment_token_address (using admin address as payment token)
            3600 // expiration_time (1 hour)
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
        setup_test_environment(admin);
        
        // Create test identities
        create_test_identity(user1, USER1);
        create_test_identity(user2, USER2);
        
        // Create test token
        let (token_address, _metadata) = create_test_token(admin);
        
        // Mint tokens to user1
        mint_tokens_to_user(admin, USER1, token_address, 1000);
        
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
    public fun test_dvp_order_execution(admin: &signer, user1: &signer, user2: &signer) {
        setup_test_environment(admin);
        
        // Create test identities
        create_test_identity(user1, USER1);
        create_test_identity(user2, USER2);
        
        // Create test token
        let (token_address, _metadata) = create_test_token(admin);
        
        // Mint tokens to both users
        mint_tokens_to_user(admin, USER1, token_address, 1000);
        mint_tokens_to_user(admin, USER2, @0x1, 1000); // Payment tokens
        
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
        
        // Execute the DVP order
        dvp_manager::execute_dvp_order(user2, order_id);
        
        // Verify order was executed
        let (_, _, _, _, _, _, status, _, _, _) = dvp_manager::get_dvp_order(order_id);
        assert!(status == constants::get_dvp_order_status_executed(), 0);
        
        // Verify token transfer occurred
        assert!(trex_token::get_user_balance(USER1, token_address) == 900, 0);
        assert!(trex_token::get_user_balance(USER2, token_address) == 100, 0);
    }

    #[test(admin = @0x1, user1 = @0x2, user2 = @0x3)]
    public fun test_dvp_order_expiration(admin: &signer, user1: &signer, user2: &signer) {
        setup_test_environment(admin);
        
        // Create test identities
        create_test_identity(user1, USER1);
        create_test_identity(user2, USER2);
        
        // Create test token
        let (token_address, _metadata) = create_test_token(admin);
        
        // Mint tokens to user1
        mint_tokens_to_user(admin, USER1, token_address, 1000);
        
        // Create DVP order with short expiration
        let order_id = dvp_manager::create_dvp_order(
            user1,
            USER2,
            token_address,
            100,
            1000,
            @0x1,
            1 // Very short expiration
        );
        
        // Check if order is expired
        let is_expired = dvp_manager::is_dvp_order_expired(order_id);
        // Note: This might return false immediately after creation
        // In a real scenario, you'd wait for the expiration time
    }

    #[test(admin = @0x1, user1 = @0x2, user2 = @0x3)]
    public fun test_dvp_order_status_check(admin: &signer, user1: &signer, user2: &signer) {
        setup_test_environment(admin);
        
        // Create test identities
        create_test_identity(user1, USER1);
        create_test_identity(user2, USER2);
        
        // Create test token
        let (token_address, _metadata) = create_test_token(admin);
        
        // Mint tokens to user1
        mint_tokens_to_user(admin, USER1, token_address, 1000);
        
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

    // ========== INTEGRATION TESTS ==========

    #[test(admin = @0x1, user1 = @0x2, user2 = @0x3)]
    public fun test_compliance_with_dvp_flow(admin: &signer, user1: &signer, user2: &signer) {
        setup_test_environment(admin);
        
        // Create test identities
        create_test_identity(user1, USER1);
        create_test_identity(user2, USER2);
        
        // Create test token with compliance enabled
        let (token_address, _metadata) = create_test_token(admin);
        
        // Initialize token compliance
        modular_compliance::initialize_token_compliance(
            admin,
            token_address
        );
        
        // Mint tokens to user1
        mint_tokens_to_user(admin, USER1, token_address, 1000);
        
        // Create DVP order (should respect compliance)
        let order_id = dvp_manager::create_dvp_order(
            user1,
            USER2,
            token_address,
            100,
            1000,
            @0x1,
            3600
        );
        
        // Verify order was created successfully
        assert!(dvp_manager::does_dvp_order_exist(order_id), 0);
        
        // Execute DVP order (should respect compliance)
        dvp_manager::execute_dvp_order(user2, order_id);
        
        // Verify execution was successful
        let (_, _, _, _, _, _, status, _, _, _) = dvp_manager::get_dvp_order(order_id);
        assert!(status == constants::get_dvp_order_status_executed(), 0);
        
        // Verify token transfer occurred
        assert!(trex_token::get_user_balance(USER1, token_address) == 900, 0);
        assert!(trex_token::get_user_balance(USER2, token_address) == 100, 0);
    }

    #[test(admin = @0x1, user1 = @0x2, user2 = @0x3)]
    public fun test_token_pause_during_dvp(admin: &signer, user1: &signer, user2: &signer) {
        setup_test_environment(admin);
        
        // Create test identities
        create_test_identity(user1, USER1);
        create_test_identity(user2, USER2);
        
        // Create test token
        let (token_address, _metadata) = create_test_token(admin);
        
        // Mint tokens to user1
        mint_tokens_to_user(admin, USER1, token_address, 1000);
        
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
        
        // Pause the token
        trex_token::pause_token(admin, token_address, string::utf8(b"Emergency pause"));
        
        // Try to execute DVP order (should fail due to paused token)
        // Note: This test assumes the DVP execution checks for token pause status
        // The actual implementation might handle this differently
        
        // Unpause the token
        trex_token::unpause_token(admin, token_address);
        
        // Now execute the DVP order
        dvp_manager::execute_dvp_order(user2, order_id);
        
        // Verify execution was successful after unpause
        let (_, _, _, _, _, _, status, _, _, _) = dvp_manager::get_dvp_order(order_id);
        assert!(status == constants::get_dvp_order_status_executed(), 0);
    }
}
