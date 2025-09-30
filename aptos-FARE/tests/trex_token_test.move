/// Test module for T-REX compliant token system
/// Comprehensive tests for all modules

module FARE::trex_token_test {
    use std::signer;
    use std::vector;
    use std::string;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use FARE::constants;
    use FARE::access_control;
    use FARE::onchain_identity;
    use FARE::claim_issuers;
    use FARE::trex_token;
    use FARE::token_information;
    use FARE::token_roles;
    use FARE::modular_compliance;
    use FARE::transfer_rules;
    use FARE::country_restrictions;
    use FARE::dvp_manager;
    use FARE::dve_exchange;
    use FARE::settlement;

    // ========== TEST ACCOUNTS ==========
    
    const ADMIN: address = @0x1;
    const USER1: address = @0x2;
    const USER2: address = @0x3;
    const ISSUER1: address = @0x4;
    const EXCHANGE1: address = @0x5;

    // ========== INITIALIZATION TESTS ==========
    
    #[test(admin = @0x1)]
    public fun test_initialize_system(admin: &signer) {
        // Initialize all modules
        access_control::initialize(admin);
        onchain_identity::initialize(admin);
        claim_issuers::initialize(admin);
        trex_token::initialize(admin);
        token_information::initialize(admin);
        token_roles::initialize(admin);
        modular_compliance::initialize(admin);
        transfer_rules::initialize(admin);
        country_restrictions::initialize(admin);
        dvp_manager::initialize(admin);
        dve_exchange::initialize(admin);
        settlement::initialize(admin);
        
        // Verify initialization
        assert!(access_control::has_role(admin, constants::get_role_token_owner()), 0);
        assert!(access_control::has_role(admin, constants::get_role_compliance_officer()), 0);
        assert!(access_control::has_role(admin, constants::get_role_token_agent()), 0);
        assert!(access_control::has_role(admin, constants::get_role_emergency_pause()), 0);
    }

    // ========== IDENTITY TESTS ==========
    
    #[test(admin = @0x1, user1 = @0x2)]
    public fun test_create_identity(admin: &signer, user1: &signer) {
        // Initialize system
        access_control::initialize(admin);
        onchain_identity::initialize(admin);
        
        // Create identity for user1
        let identity_object = onchain_identity::create_identity(
            user1,
            constants::get_kyc_level_basic(),
            constants::get_investor_type_retail(),
            b"US",
            946684800 // 2000-01-01
        );
        
        // Verify identity creation
        assert!(onchain_identity::has_identity(USER1), 0);
        let (has_identity, kyc_level, investor_type, age_verified, pep_status, sanctions_checked, country_code) = 
            onchain_identity::get_identity_status(USER1);
        assert!(has_identity, 0);
        assert!(kyc_level == constants::get_kyc_level_basic(), 0);
        assert!(investor_type == constants::get_investor_type_retail(), 0);
        assert!(country_code == b"US", 0);
    }
    
    #[test(admin = @0x1, issuer1 = @0x4)]
    public fun test_register_claim_issuer(admin: &signer, issuer1: &signer) {
        // Initialize system
        access_control::initialize(admin);
        claim_issuers::initialize(admin);
        
        // Register claim issuer
        claim_issuers::register_issuer(
            admin,
            ISSUER1,
            string::utf8(b"Test Issuer"),
            string::utf8(b"https://test-issuer.com"),
            vector::empty(),
            1000,
            true,
            true
        );
        
        // Verify issuer registration
        assert!(claim_issuers::is_issuer_active(ISSUER1), 0);
        let (name, url, is_active, claim_count, allowed_topics, reputation_score, created_at, updated_at) = 
            claim_issuers::get_issuer_info(ISSUER1);
        assert!(name == string::utf8(b"Test Issuer"), 0);
        assert!(url == string::utf8(b"https://test-issuer.com"), 0);
        assert!(is_active, 0);
    }

    // ========== TOKEN CREATION TESTS ==========
    
    #[test(admin = @0x1)]
    public fun test_create_trex_token(admin: &signer) {
        // Initialize system
        access_control::initialize(admin);
        trex_token::initialize(admin);
        token_information::initialize(admin);
        token_roles::initialize(admin);
        modular_compliance::initialize(admin);
        
        // Create T-REX token
        let (token_address, metadata) = trex_token::create_trex_token(
            admin,
            string::utf8(b"Test Token"),
            string::utf8(b"TEST"),
            8,
            string::utf8(b"Test T-REX Token"),
            string::utf8(b"https://test-token.com/icon.png"),
            string::utf8(b"https://test-token.com"),
            1000000000000000000, // 1B tokens with 8 decimals
            true, // Supply cap enabled
            true, // Compliance enabled
            true, // Identity verification required
            constants::get_kyc_level_basic(),
            constants::get_investor_type_retail(),
            true, // Country restrictions enabled
            true, // Transfer restrictions enabled
            true  // Balance restrictions enabled
        );
        
        // Verify token creation
        assert!(trex_token::is_trex_compliant(token_address), 0);
        let (name, symbol, description, decimals, icon_uri, project_uri, creator, created_at, updated_at) = 
            token_information::get_token_metadata(token_address);
        assert!(name == string::utf8(b"Test Token"), 0);
        assert!(symbol == string::utf8(b"TEST"), 0);
        assert!(decimals == 8, 0);
        
        let (is_trex_compliant, compliance_level, required_kyc_level, required_investor_type, 
             country_restrictions_enabled, transfer_restrictions_enabled, balance_restrictions_enabled, updated_at) = 
            token_information::get_token_compliance_info(token_address);
        assert!(is_trex_compliant, 0);
        assert!(required_kyc_level == constants::get_kyc_level_basic(), 0);
        assert!(required_investor_type == constants::get_investor_type_retail(), 0);
        assert!(country_restrictions_enabled, 0);
        assert!(transfer_restrictions_enabled, 0);
        assert!(balance_restrictions_enabled, 0);
    }

    // ========== COMPLIANCE TESTS ==========
    
    #[test(admin = @0x1)]
    public fun test_compliance_modules(admin: &signer) {
        // Initialize system
        access_control::initialize(admin);
        modular_compliance::initialize(admin);
        transfer_rules::initialize(admin);
        country_restrictions::initialize(admin);
        
        // Initialize token compliance
        modular_compliance::initialize_token_compliance(admin, @0x100);
        
        // Enable compliance modules
        modular_compliance::enable_compliance_module(
            admin,
            @0x100,
            constants::get_compliance_module_transfer_restrictions(),
            1,
            vector::empty()
        );
        
        modular_compliance::enable_compliance_module(
            admin,
            @0x100,
            constants::get_compliance_module_country_restrictions(),
            2,
            vector::empty()
        );
        
        // Verify compliance modules
        assert!(modular_compliance::is_compliance_module_enabled(@0x100, constants::get_compliance_module_transfer_restrictions()), 0);
        assert!(modular_compliance::is_compliance_module_enabled(@0x100, constants::get_compliance_module_country_restrictions()), 0);
        
        let enabled_modules = modular_compliance::get_enabled_compliance_modules(@0x100);
        assert!(vector::length(&enabled_modules) == 2, 0);
    }
    
    #[test(admin = @0x1)]
    public fun test_transfer_restrictions(admin: &signer) {
        // Initialize system
        access_control::initialize(admin);
        transfer_rules::initialize(admin);
        
        // Set transfer restrictions for user
        transfer_rules::set_user_transfer_restrictions(
            admin,
            USER1,
            1000000000000000000, // 1 token max transfer
            10000000000000000000, // 10 tokens daily limit
            100000000000000000000, // 100 tokens monthly limit
            10, // 10 transfers per day
            100, // 100 transfers per month
            3600 // 1 hour transfer lock
        );
        
        // Verify transfer restrictions
        let (max_transfer_amount, daily_transfer_limit, monthly_transfer_limit, 
             daily_transfer_count, monthly_transfer_count, transfer_lock_duration, 
             last_transfer_timestamp, daily_volume_used, monthly_volume_used, 
             daily_count_used, monthly_count_used, last_daily_reset, last_monthly_reset) = 
            transfer_rules::get_user_transfer_restrictions(USER1);
        assert!(max_transfer_amount == 1000000000000000000, 0);
        assert!(daily_transfer_limit == 10000000000000000000, 0);
        assert!(monthly_transfer_limit == 100000000000000000000, 0);
        assert!(daily_transfer_count == 10, 0);
        assert!(monthly_transfer_count == 100, 0);
        assert!(transfer_lock_duration == 3600, 0);
    }
    
    #[test(admin = @0x1)]
    public fun test_country_restrictions(admin: &signer) {
        // Initialize system
        access_control::initialize(admin);
        country_restrictions::initialize(admin);
        
        // Block a country
        country_restrictions::block_country(
            admin,
            b"CN",
            string::utf8(b"Sanctions compliance")
        );
        
        // Set country restriction
        country_restrictions::set_country_restriction(
            admin,
            b"US",
            false, // Not blocked
            true,  // Whitelisted
            1000000000000000000, // 1 token max transfer
            10000000000000000000, // 10 tokens daily limit
            100000000000000000000, // 100 tokens monthly limit
            false, // No approval required
            string::utf8(b"")
        );
        
        // Verify country restrictions
        assert!(country_restrictions::is_country_blocked(b"CN"), 0);
        assert!(!country_restrictions::is_country_blocked(b"US"), 0);
        assert!(country_restrictions::is_country_whitelisted(b"US"), 0);
        
        let (is_blocked, is_whitelisted, max_transfer_amount, daily_transfer_limit, 
             monthly_transfer_limit, requires_approval, restriction_reason, created_at, updated_at) = 
            country_restrictions::get_country_restriction(b"US");
        assert!(!is_blocked, 0);
        assert!(is_whitelisted, 0);
        assert!(max_transfer_amount == 1000000000000000000, 0);
    }

    // ========== DVP TESTS ==========
    
    #[test(admin = @0x1, user1 = @0x2, user2 = @0x3)]
    public fun test_dvp_order(admin: &signer, user1: &signer, user2: &signer) {
        // Initialize system
        access_control::initialize(admin);
        dvp_manager::initialize(admin);
        trex_token::initialize(admin);
        token_information::initialize(admin);
        token_roles::initialize(admin);
        modular_compliance::initialize(admin);
        
        // Create T-REX token
        let (token_address, _) = trex_token::create_trex_token(
            admin,
            string::utf8(b"Test Token"),
            string::utf8(b"TEST"),
            8,
            string::utf8(b"Test T-REX Token"),
            string::utf8(b"https://test-token.com/icon.png"),
            string::utf8(b"https://test-token.com"),
            1000000000000000000,
            true,
            true,
            true,
            constants::get_kyc_level_basic(),
            constants::get_investor_type_retail(),
            true,
            true,
            true
        );
        
        // Create DVP order
        let order_id = dvp_manager::create_dvp_order(
            user1,
            USER2,
            token_address,
            100000000000000000, // 0.1 tokens
            100000000, // 0.1 APT
            @0x1, // APT token address
            timestamp::now_seconds() + 86400 // 24 hours
        );
        
        // Verify DVP order creation
        assert!(dvp_manager::does_dvp_order_exist(order_id), 0);
        let (seller, buyer, order_token_address, token_amount, payment_amount, 
             payment_token_address, status, expiry, created_at, updated_at) = 
            dvp_manager::get_dvp_order(order_id);
        assert!(seller == USER1, 0);
        assert!(buyer == USER2, 0);
        assert!(order_token_address == token_address, 0);
        assert!(token_amount == 100000000000000000, 0);
        assert!(payment_amount == 100000000, 0);
        assert!(status == constants::get_dvp_order_status_pending(), 0);
        
        // Execute DVP order
        dvp_manager::execute_dvp_order(user2, order_id);
        
        // Verify DVP order execution
        let (_, _, _, _, _, _, status, _, _, _) = dvp_manager::get_dvp_order(order_id);
        assert!(status == constants::get_dvp_order_status_executed(), 0);
    }

    // ========== DVE TESTS ==========
    
    #[test(admin = @0x1, exchange1 = @0x5, user1 = @0x2)]
    public fun test_dve_exchange(admin: &signer, exchange1: &signer, user1: &signer) {
        // Initialize system
        access_control::initialize(admin);
        dve_exchange::initialize(admin);
        trex_token::initialize(admin);
        token_information::initialize(admin);
        token_roles::initialize(admin);
        modular_compliance::initialize(admin);
        
        // Create T-REX token
        let (token_address, _) = trex_token::create_trex_token(
            admin,
            string::utf8(b"Test Token"),
            string::utf8(b"TEST"),
            8,
            string::utf8(b"Test T-REX Token"),
            string::utf8(b"https://test-token.com/icon.png"),
            string::utf8(b"https://test-token.com"),
            1000000000000000000,
            true,
            true,
            true,
            constants::get_kyc_level_basic(),
            constants::get_investor_type_retail(),
            true,
            true,
            true
        );
        
        // Register exchange
        dve_exchange::register_exchange(
            admin,
            EXCHANGE1,
            string::utf8(b"Test Exchange"),
            string::utf8(b"https://test-exchange.com"),
            constants::get_exchange_compliance_full(),
            vector::empty(),
            3600, // 1 hour settlement delay
            true, // Netting enabled
            10000000000000000000, // 10 tokens daily limit
            100000000000000000000  // 100 tokens monthly limit
        );
        
        // Verify exchange registration
        assert!(dve_exchange::is_exchange_registered(EXCHANGE1), 0);
        assert!(dve_exchange::is_exchange_active(EXCHANGE1), 0);
        let (name, url, compliance_level, is_active, transfer_limits, settlement_delay, 
             netting_enabled, daily_volume_limit, monthly_volume_limit, current_daily_volume, 
             current_monthly_volume, last_daily_reset, last_monthly_reset, created_at) = 
            dve_exchange::get_exchange_info(EXCHANGE1);
        assert!(name == string::utf8(b"Test Exchange"), 0);
        assert!(url == string::utf8(b"https://test-exchange.com"), 0);
        assert!(compliance_level == constants::get_exchange_compliance_full(), 0);
        assert!(is_active, 0);
        assert!(netting_enabled, 0);
        
        // Create DVE order
        let order_id = dve_exchange::create_dve_order(
            user1,
            EXCHANGE1,
            token_address,
            100000000000000000, // 0.1 tokens
            1, // Buy order
            timestamp::now_seconds() + 86400 // 24 hours
        );
        
        // Verify DVE order creation
        let (exchange_address, user_address, order_token_address, token_amount, 
             order_type, status, expiry, created_at, updated_at) = 
            dve_exchange::get_dve_order(order_id);
        assert!(exchange_address == EXCHANGE1, 0);
        assert!(user_address == USER1, 0);
        assert!(order_token_address == token_address, 0);
        assert!(token_amount == 100000000000000000, 0);
        assert!(order_type == 1, 0);
        assert!(status == 1, 0); // Pending
        
        // Execute DVE order
        dve_exchange::execute_dve_order(user1, order_id);
        
        // Verify DVE order execution
        let (_, _, _, _, _, status, _, _, _) = dve_exchange::get_dve_order(order_id);
        assert!(status == 2, 0); // Executed
    }

    // ========== SETTLEMENT TESTS ==========
    
    #[test(admin = @0x1, user1 = @0x2, user2 = @0x3)]
    public fun test_settlement(admin: &signer, user1: &signer, user2: &signer) {
        // Initialize system
        access_control::initialize(admin);
        settlement::initialize(admin);
        trex_token::initialize(admin);
        token_information::initialize(admin);
        token_roles::initialize(admin);
        modular_compliance::initialize(admin);
        
        // Create T-REX token
        let (token_address, _) = trex_token::create_trex_token(
            admin,
            string::utf8(b"Test Token"),
            string::utf8(b"TEST"),
            8,
            string::utf8(b"Test T-REX Token"),
            string::utf8(b"https://test-token.com/icon.png"),
            string::utf8(b"https://test-token.com"),
            1000000000000000000,
            true,
            true,
            true,
            constants::get_kyc_level_basic(),
            constants::get_investor_type_retail(),
            true,
            true,
            true
        );
        
        // Request settlement
        let request_id = settlement::request_settlement(
            admin,
            1, // DVP settlement type
            1, // Order ID
            USER1,
            USER2,
            token_address,
            100000000000000000, // 0.1 tokens
            100000000, // 0.1 APT
            @0x1, // APT token address
            3600 // 1 hour settlement delay
        );
        
        // Verify settlement request
        assert!(settlement::does_settlement_request_exist(request_id), 0);
        let (settlement_type, order_id, seller, buyer, request_token_address, 
             token_amount, payment_amount, payment_token_address, status, 
             settlement_delay, created_at, settled_at) = 
            settlement::get_settlement_request(request_id);
        assert!(settlement_type == 1, 0);
        assert!(order_id == 1, 0);
        assert!(seller == USER1, 0);
        assert!(buyer == USER2, 0);
        assert!(request_token_address == token_address, 0);
        assert!(token_amount == 100000000000000000, 0);
        assert!(payment_amount == 100000000, 0);
        assert!(status == 1, 0); // Pending
        
        // Create settlement batch
        let batch_id = settlement::create_settlement_batch(
            admin,
            string::utf8(b"Test Batch"),
            vector::empty()
        );
        
        // Verify settlement batch
        let (batch_name, settlement_requests, status, created_at, executed_at) = 
            settlement::get_settlement_batch(batch_id);
        assert!(batch_name == string::utf8(b"Test Batch"), 0);
        assert!(status == 1, 0); // Pending
    }

    // ========== INTEGRATION TESTS ==========
    
    #[test(admin = @0x1, user1 = @0x2, user2 = @0x3, issuer1 = @0x4)]
    public fun test_full_workflow(admin: &signer, user1: &signer, user2: &signer, issuer1: &signer) {
        // Initialize entire system
        access_control::initialize(admin);
        onchain_identity::initialize(admin);
        claim_issuers::initialize(admin);
        trex_token::initialize(admin);
        token_information::initialize(admin);
        token_roles::initialize(admin);
        modular_compliance::initialize(admin);
        transfer_rules::initialize(admin);
        country_restrictions::initialize(admin);
        dvp_manager::initialize(admin);
        dve_exchange::initialize(admin);
        settlement::initialize(admin);
        
        // Register claim issuer
        claim_issuers::register_issuer(
            admin,
            ISSUER1,
            string::utf8(b"Test Issuer"),
            string::utf8(b"https://test-issuer.com"),
            vector::empty(),
            1000,
            true,
            true
        );
        
        // Create identities
        let identity1 = onchain_identity::create_identity(
            user1,
            constants::get_kyc_level_basic(),
            constants::get_investor_type_retail(),
            b"US",
            946684800
        );
        
        let identity2 = onchain_identity::create_identity(
            user2,
            constants::get_kyc_level_basic(),
            constants::get_investor_type_retail(),
            b"US",
            946684800
        );
        
        // Create T-REX token
        let (token_address, _) = trex_token::create_trex_token(
            admin,
            string::utf8(b"Test Token"),
            string::utf8(b"TEST"),
            8,
            string::utf8(b"Test T-REX Token"),
            string::utf8(b"https://test-token.com/icon.png"),
            string::utf8(b"https://test-token.com"),
            1000000000000000000,
            true,
            true,
            true,
            constants::get_kyc_level_basic(),
            constants::get_investor_type_retail(),
            true,
            true,
            true
        );
        
        // Set up compliance
        modular_compliance::initialize_token_compliance(admin, token_address);
        modular_compliance::enable_compliance_module(
            admin,
            token_address,
            constants::get_compliance_module_transfer_restrictions(),
            1,
            vector::empty()
        );
        
        // Set transfer restrictions
        transfer_rules::set_user_transfer_restrictions(
            admin,
            USER1,
            1000000000000000000,
            10000000000000000000,
            100000000000000000000,
            10,
            100,
            3600
        );
        
        // Set country restrictions
        country_restrictions::set_country_restriction(
            admin,
            b"US",
            false,
            true,
            1000000000000000000,
            10000000000000000000,
            100000000000000000000,
            false,
            string::utf8(b"")
        );
        
        // Create DVP order
        let order_id = dvp_manager::create_dvp_order(
            user1,
            USER2,
            token_address,
            100000000000000000,
            100000000,
            @0x1,
            timestamp::now_seconds() + 86400
        );
        
        // Execute DVP order
        dvp_manager::execute_dvp_order(user2, order_id);
        
        // Verify end-to-end workflow
        assert!(onchain_identity::has_identity(USER1), 0);
        assert!(onchain_identity::has_identity(USER2), 0);
        assert!(claim_issuers::is_issuer_active(ISSUER1), 0);
        assert!(trex_token::is_trex_compliant(token_address), 0);
        assert!(modular_compliance::is_compliance_module_enabled(token_address, constants::get_compliance_module_transfer_restrictions()), 0);
        assert!(dvp_manager::does_dvp_order_exist(order_id), 0);
        
        let (_, _, _, _, _, _, status, _, _, _) = dvp_manager::get_dvp_order(order_id);
        assert!(status == constants::get_dvp_order_status_executed(), 0);
    }
}
