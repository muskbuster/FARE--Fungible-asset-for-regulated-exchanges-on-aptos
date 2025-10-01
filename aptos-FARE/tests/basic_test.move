/// Basic test module for T-REX compliant token system
/// Tests only existing functions

module FARE::basic_test {
    use std::signer;
    use std::string;
    use std::vector;
    use std::timestamp;
    use aptos_framework::account;
    
    use FARE::constants;
    use FARE::access_control;

    // Test accounts
    const ADMIN: address = @0x1;
    const USER1: address = @0x2;

    #[test(admin = @0x1)]
    public fun test_initialize_access_control(admin: &signer) {
        // Initialize the account first
        account::create_account_for_test(signer::address_of(admin));
        
        // Initialize timestamp for the framework
        timestamp::set_time_has_started_for_testing(admin);
        
        // Initialize access control
        access_control::initialize(admin);
        
        // Verify admin has all roles that are granted during initialization
        assert!(access_control::has_role(@0x1, constants::get_role_token_owner()), 0);
        assert!(access_control::has_role(@0x1, constants::get_role_compliance_officer()), 0);
        assert!(access_control::has_role(@0x1, constants::get_role_token_agent()), 0);
        assert!(access_control::has_role(@0x1, constants::get_role_emergency_pause()), 0);
    }

    #[test(admin = @0x1)]
    public fun test_constants_functions(admin: &signer) {
        // Test that constants functions work
        let kyc_level = constants::get_kyc_level_basic();
        assert!(kyc_level == 1, 0);
        
        let investor_type = constants::get_investor_type_retail();
        assert!(investor_type == 1, 0);
        
        let role_type = constants::get_role_token_owner();
        assert!(role_type == 1, 0);
        
        let error_code = constants::get_identity_not_found_error();
        assert!(error_code == 1001, 0);
    }

    #[test(admin = @0x1)]
    public fun test_validation_functions(admin: &signer) {
        // Test validation functions
        assert!(constants::is_valid_kyc_level(1), 0);
        assert!(!constants::is_valid_kyc_level(5), 0);
        
        assert!(constants::is_valid_investor_type(1), 0);
        assert!(!constants::is_valid_investor_type(0), 0);
        
        assert!(constants::is_valid_role_type(1), 0);
        assert!(!constants::is_valid_role_type(0), 0);
        
        assert!(constants::is_valid_amount(1000), 0);
        assert!(!constants::is_valid_amount(0), 0);
    }
}
