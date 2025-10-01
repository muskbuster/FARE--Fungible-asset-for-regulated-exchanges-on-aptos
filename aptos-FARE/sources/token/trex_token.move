/// T-REX Token module for T-REX compliant token system
/// Main token implementation with compliance hooks and T-REX features
///
/// IMPORTANT DISCLAIMER:
/// This implementation does NOT use the Aptos Fungible Asset (FA) standard for balance tracking
/// or transfer logic. Instead, it uses a completely custom balance management system with:
/// - Custom user_balances table for tracking token balances
/// - Custom transfer logic that bypasses the standard FA framework
/// - Custom minting system that directly updates internal balance tables


module FARE::trex_token {
    use std::vector;
    use std::string::{Self, String};
    use std::table::{Self, Table};
    use std::error;
    use std::signer;
    use std::timestamp;
    use std::option;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object};
    use FARE::constants;
    use FARE::token_information;
    use FARE::token_roles;
    use FARE::modular_compliance;
    use FARE::onchain_identity;

    // ========== STRUCTS ==========
    
    /// T-REX token configuration
    struct TRexTokenConfig has store, copy, drop {
        /// Token address
        token_address: address,
        /// Token metadata object
        metadata: Object<Metadata>,
        /// Whether compliance is enabled
        compliance_enabled: bool,
        /// Whether identity verification is required
        identity_verification_required: bool,
        /// Required KYC level
        required_kyc_level: u8,
        /// Required investor type
        required_investor_type: u8,
        /// Country restrictions enabled
        country_restrictions_enabled: bool,
        /// Transfer restrictions enabled
        transfer_restrictions_enabled: bool,
        /// Balance restrictions enabled
        balance_restrictions_enabled: bool,
        /// Created timestamp
        created_at: u64,
        /// Last updated timestamp
        updated_at: u64,
    }
    
    /// Transfer with compliance result
    struct TransferWithComplianceResult has store, copy, drop {
        /// Whether transfer was successful
        success: bool,
        /// Error code if failed
        error_code: u64,
        /// Error message
        error_message: String,
        /// Compliance check results
        compliance_results: vector<u8>,
        /// Transfer timestamp
        transferred_at: u64,
    }
    
    /// T-REX token registry
    struct TRexTokenRegistry has key {
        /// Map of token address to T-REX token config
        trex_tokens: Table<address, TRexTokenConfig>,
        /// Map of user to their token balances
        user_balances: Table<address, Table<address, u64>>,
        /// Map of user to their transfer history
        user_transfer_history: Table<address, Table<u64, TransferRecord>>,
        /// Next transfer ID
        next_transfer_id: u64,
        /// Events
        trex_token_created_events: EventHandle<TRexTokenCreatedEvent>,
        token_minted_events: EventHandle<TokenMintedEvent>,
        transfer_with_compliance_events: EventHandle<TransferWithComplianceEvent>,
        compliance_check_failed_events: EventHandle<ComplianceCheckFailedEvent>,
        token_paused_events: EventHandle<TokenPausedEvent>,
        forced_transfer_events: EventHandle<ForcedTransferEvent>,
    }
    
    /// Transfer record
    struct TransferRecord has store, copy, drop {
        /// Transfer ID
        transfer_id: u64,
        /// From address
        from: address,
        /// To address
        to: address,
        /// Amount
        amount: u64,
        /// Transfer type
        transfer_type: u8,
        /// Compliance status
        compliance_status: u8,
        /// Transfer timestamp
        timestamp: u64,
    }
    
    /// T-REX token created event
    struct TRexTokenCreatedEvent has store, drop {
        token_address: address,
        name: String,
        symbol: String,
        decimals: u8,
        compliance_enabled: bool,
        created_by: address,
        created_at: u64,
    }
    
    /// Token minted event
    struct TokenMintedEvent has store, drop {
        token_address: address,
        admin: address,
        to: address,
        amount: u64,
        minted_at: u64,
    }
    
    /// Transfer with compliance event
    struct TransferWithComplianceEvent has store, drop {
        token_address: address,
        from: address,
        to: address,
        amount: u64,
        compliance_passed: bool,
        transferred_at: u64,
    }
    
    /// Compliance check failed event
    struct ComplianceCheckFailedEvent has store, drop {
        token_address: address,
        from: address,
        to: address,
        amount: u64,
        error_code: u64,
        error_message: String,
        failed_at: u64,
    }
    
    /// Token paused event
    struct TokenPausedEvent has store, drop {
        token_address: address,
        paused_by: address,
        pause_reason: String,
        paused_at: u64,
    }
    
    /// Forced transfer event
    struct ForcedTransferEvent has store, drop {
        token_address: address,
        from: address,
        to: address,
        amount: u64,
        forced_by: address,
        transfer_reason: String,
        transferred_at: u64,
    }

    // ========== INITIALIZATION ==========
    
    /// Initialize T-REX token registry
    public fun initialize(account: &signer) {
        let account_addr = signer::address_of(account);
        
        // Ensure account is not already initialized
        assert!(!exists<TRexTokenRegistry>(account_addr), constants::get_access_control_not_authorized_error());
        
        let registry = TRexTokenRegistry {
            trex_tokens: table::new(),
            user_balances: table::new(),
            user_transfer_history: table::new(),
            next_transfer_id: 1,
            trex_token_created_events: account::new_event_handle<TRexTokenCreatedEvent>(account),
            token_minted_events: account::new_event_handle<TokenMintedEvent>(account),
            transfer_with_compliance_events: account::new_event_handle<TransferWithComplianceEvent>(account),
            compliance_check_failed_events: account::new_event_handle<ComplianceCheckFailedEvent>(account),
            token_paused_events: account::new_event_handle<TokenPausedEvent>(account),
            forced_transfer_events: account::new_event_handle<ForcedTransferEvent>(account),
        };
        
        move_to(account, registry);
    }

    // ========== T-REX TOKEN CREATION ==========
    
    /// Create a new T-REX compliant token
    public fun create_trex_token(
        account: &signer,
        name: String,
        symbol: String,
        decimals: u8,
        description: String,
        icon_uri: String,
        project_uri: String,
        max_supply: u64,
        supply_cap_enabled: bool,
        compliance_enabled: bool,
        identity_verification_required: bool,
        required_kyc_level: u8,
        required_investor_type: u8,
        country_restrictions_enabled: bool,
        transfer_restrictions_enabled: bool,
        balance_restrictions_enabled: bool
    ): (address, Object<Metadata>) acquires TRexTokenRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TRexTokenRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Validate parameters
        assert!(decimals <= 18, constants::get_invalid_parameter_error());
        assert!(constants::is_valid_kyc_level(required_kyc_level), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_investor_type(required_investor_type), constants::get_invalid_parameter_error());
        
        // Create an object to hold the fungible asset metadata
        let constructor_ref = object::create_named_object(account, *string::bytes(&name));
        
        // Add fungibility to the object
        let metadata = fungible_asset::add_fungibility(
            &constructor_ref,
            option::some(max_supply as u128), // Maximum supply
            name,
            symbol,
            decimals,
            icon_uri,
            project_uri,
        );
        
        let token_address = object::object_address(&metadata);
        
        // Register token metadata
        token_information::register_token_metadata(
            account,
            token_address,
            name,
            symbol,
            description,
            decimals,
            icon_uri,
            project_uri
        );
        
        // Initialize token supply information
        token_information::initialize_token_supply(
            account,
            token_address,
            max_supply,
            supply_cap_enabled
        );
        
        // Initialize token compliance information
        token_information::initialize_token_compliance(
            account,
            token_address,
            3, // Full compliance level
            required_kyc_level,
            required_investor_type,
            country_restrictions_enabled,
            transfer_restrictions_enabled,
            balance_restrictions_enabled
        );
        
        // Initialize token status
        token_information::initialize_token_status(account, token_address);
        
        // Initialize token compliance configuration
        modular_compliance::initialize_token_compliance(account, token_address);
        
        // Create T-REX token configuration
        let trex_config = TRexTokenConfig {
            token_address,
            metadata,
            compliance_enabled,
            identity_verification_required,
            required_kyc_level,
            required_investor_type,
            country_restrictions_enabled,
            transfer_restrictions_enabled,
            balance_restrictions_enabled,
            created_at: current_time,
            updated_at: current_time,
        };
        
        table::add(&mut registry.trex_tokens, token_address, trex_config);
        
        // Emit event
        event::emit_event(&mut registry.trex_token_created_events, TRexTokenCreatedEvent {
            token_address,
            name,
            symbol,
            decimals,
            compliance_enabled,
            created_by: account_addr,
            created_at: current_time,
        });
        
        (token_address, metadata)
    }

    // ========== MINTING FUNCTIONS ==========
    
    /// Mint tokens to a user (admin only) - simplified version for testing
    public fun mint_tokens(
        admin: &signer,
        token_address: address,
        to: address,
        amount: u64
    ) acquires TRexTokenRegistry {
        let admin_addr = signer::address_of(admin);
        let registry = borrow_global_mut<TRexTokenRegistry>(admin_addr);
        
        // Check if token is T-REX compliant
        assert!(table::contains(&registry.trex_tokens, token_address), constants::get_compliance_module_not_found_error());
        
        // Update user balance tracking (simplified for testing)
        if (!table::contains(&registry.user_balances, to)) {
            table::add(&mut registry.user_balances, to, table::new());
        };
        
        let user_balances = table::borrow_mut(&mut registry.user_balances, to);
        if (!table::contains(user_balances, token_address)) {
            table::add(user_balances, token_address, 0);
        };
        
        let current_balance = table::borrow_mut(user_balances, token_address);
        *current_balance = *current_balance + amount;
        
        // Emit mint event
        event::emit_event(&mut registry.token_minted_events, TokenMintedEvent {
            token_address,
            admin: admin_addr,
            to,
            amount,
            minted_at: timestamp::now_seconds(),
        });
    }
    
    /// Mint tokens to a user with compliance checks - simplified version for testing
    public fun mint_tokens_with_compliance(
        admin: &signer,
        token_address: address,
        to: address,
        amount: u64
    ) acquires TRexTokenRegistry {
        let admin_addr = signer::address_of(admin);
        let registry = borrow_global_mut<TRexTokenRegistry>(admin_addr);
        
        // Check if token is T-REX compliant
        assert!(table::contains(&registry.trex_tokens, token_address), constants::get_compliance_module_not_found_error());
        
        let trex_config = table::borrow(&registry.trex_tokens, token_address);
        
        // Check compliance requirements if enabled
        if (trex_config.compliance_enabled) {
            // Check if user has required identity
            if (trex_config.identity_verification_required) {
                assert!(onchain_identity::has_identity(to), constants::get_identity_not_found_error());
                
                let user_kyc_level = onchain_identity::get_kyc_level(to);
                let user_investor_type = onchain_identity::get_investor_type(to);
                
                assert!(user_kyc_level >= trex_config.required_kyc_level, constants::get_insufficient_kyc_level_error());
                assert!(user_investor_type >= trex_config.required_investor_type, constants::get_insufficient_investor_type_error());
            };
        };
        
        // Update user balance tracking (simplified for testing)
        if (!table::contains(&registry.user_balances, to)) {
            table::add(&mut registry.user_balances, to, table::new());
        };
        
        let user_balances = table::borrow_mut(&mut registry.user_balances, to);
        if (!table::contains(user_balances, token_address)) {
            table::add(user_balances, token_address, 0);
        };
        
        let current_balance = table::borrow_mut(user_balances, token_address);
        *current_balance = *current_balance + amount;
        
        // Emit mint event
        event::emit_event(&mut registry.token_minted_events, TokenMintedEvent {
            token_address,
            admin: admin_addr,
            to,
            amount,
            minted_at: timestamp::now_seconds(),
        });
    }

    // ========== COMPLIANCE-AWARE TRANSFERS ==========
    
    /// Transfer tokens with compliance checking
    public fun transfer_with_compliance(
        account: &signer,
        token_address: address,
        to: address,
        amount: u64
    ): TransferWithComplianceResult acquires TRexTokenRegistry {
        let from = signer::address_of(account);
        // Registry is stored at the admin address, not the user address
        let registry = borrow_global_mut<TRexTokenRegistry>(@0x1);
        let current_time = timestamp::now_seconds();
        
        // Check if token is T-REX compliant
        assert!(table::contains(&registry.trex_tokens, token_address), constants::get_compliance_module_not_found_error());
        
        let trex_config = table::borrow(&registry.trex_tokens, token_address);
        
        // Check if token is paused
        if (token_information::is_token_paused(token_address)) {
            let result = TransferWithComplianceResult {
                success: false,
                error_code: constants::get_token_paused_error(),
                error_message: string::utf8(b"Token is paused"),
                compliance_results: vector::empty(),
                transferred_at: current_time,
            };
            
            // Emit event
            event::emit_event(&mut registry.compliance_check_failed_events, ComplianceCheckFailedEvent {
                token_address,
                from,
                to,
                amount,
                error_code: constants::get_token_paused_error(),
                error_message: string::utf8(b"Token is paused"),
                failed_at: current_time,
            });
            
            return result
        };
        
        // Check if token is frozen
        if (token_information::is_token_frozen(token_address)) {
            let result = TransferWithComplianceResult {
                success: false,
                error_code: constants::get_token_paused_error(),
                error_message: string::utf8(b"Token is frozen"),
                compliance_results: vector::empty(),
                transferred_at: current_time,
            };
            
            // Emit event
            event::emit_event(&mut registry.compliance_check_failed_events, ComplianceCheckFailedEvent {
                token_address,
                from,
                to,
                amount,
                error_code: constants::get_token_paused_error(),
                error_message: string::utf8(b"Token is frozen"),
                failed_at: current_time,
            });
            
            return result
        };
        
        // Check if accounts are frozen
        if (token_roles::is_account_frozen(token_address, from) || token_roles::is_account_frozen(token_address, to)) {
            let result = TransferWithComplianceResult {
                success: false,
                error_code: constants::get_token_account_frozen_error(),
                error_message: string::utf8(b"Account is frozen"),
                compliance_results: vector::empty(),
                transferred_at: current_time,
            };
            
            // Emit event
            event::emit_event(&mut registry.compliance_check_failed_events, ComplianceCheckFailedEvent {
                token_address,
                from,
                to,
                amount,
                error_code: constants::get_token_account_frozen_error(),
                error_message: string::utf8(b"Account is frozen"),
                failed_at: current_time,
            });
            
            return result
        };
        
        // Check identity verification if required
        if (trex_config.identity_verification_required) {
            if (!onchain_identity::has_identity(from) || !onchain_identity::has_identity(to)) {
                let result = TransferWithComplianceResult {
                    success: false,
                    error_code: constants::get_identity_not_found_error(),
                    error_message: string::utf8(b"Identity verification required"),
                    compliance_results: vector::empty(),
                    transferred_at: current_time,
                };
                
                // Emit event
                event::emit_event(&mut registry.compliance_check_failed_events, ComplianceCheckFailedEvent {
                    token_address,
                    from,
                    to,
                    amount,
                    error_code: constants::get_identity_not_found_error(),
                    error_message: string::utf8(b"Identity verification required"),
                    failed_at: current_time,
                });
                
                return result
            };
            
            // Check KYC level
            let from_kyc = onchain_identity::get_kyc_level(from);
            let to_kyc = onchain_identity::get_kyc_level(to);
            if (from_kyc < trex_config.required_kyc_level || to_kyc < trex_config.required_kyc_level) {
                let result = TransferWithComplianceResult {
                    success: false,
                    error_code: constants::get_compliance_check_failed_error(),
                    error_message: string::utf8(b"Insufficient KYC level"),
                    compliance_results: vector::empty(),
                    transferred_at: current_time,
                };
                
                // Emit event
                event::emit_event(&mut registry.compliance_check_failed_events, ComplianceCheckFailedEvent {
                    token_address,
                    from,
                    to,
                    amount,
                    error_code: constants::get_compliance_check_failed_error(),
                    error_message: string::utf8(b"Insufficient KYC level"),
                    failed_at: current_time,
                });
                
                return result
            };
            
            // Check investor type
            let from_investor_type = onchain_identity::get_investor_type(from);
            let to_investor_type = onchain_identity::get_investor_type(to);
            if (from_investor_type < trex_config.required_investor_type || to_investor_type < trex_config.required_investor_type) {
                let result = TransferWithComplianceResult {
                    success: false,
                    error_code: constants::get_compliance_check_failed_error(),
                    error_message: string::utf8(b"Insufficient investor type"),
                    compliance_results: vector::empty(),
                    transferred_at: current_time,
                };
                
                // Emit event
                event::emit_event(&mut registry.compliance_check_failed_events, ComplianceCheckFailedEvent {
                    token_address,
                    from,
                    to,
                    amount,
                    error_code: constants::get_compliance_check_failed_error(),
                    error_message: string::utf8(b"Insufficient investor type"),
                    failed_at: current_time,
                });
                
                return result
            };
        };
        
        // Perform compliance checks if enabled
        if (trex_config.compliance_enabled) {
            let compliance_result = modular_compliance::check_comprehensive_compliance(
                account,
                token_address,
                from,
                1, // Transfer check type
                vector::empty()
            );
            
            if (!modular_compliance::get_comprehensive_check_passed(&compliance_result)) {
                let result = TransferWithComplianceResult {
                    success: false,
                    error_code: modular_compliance::get_comprehensive_check_error_code(&compliance_result),
                    error_message: modular_compliance::get_comprehensive_check_error_message(&compliance_result),
                    compliance_results: modular_compliance::get_comprehensive_check_compliance_data(&compliance_result),
                    transferred_at: current_time,
                };
                
                // Emit event
                event::emit_event(&mut registry.compliance_check_failed_events, ComplianceCheckFailedEvent {
                    token_address,
                    from,
                    to,
                    amount,
                    error_code: modular_compliance::get_comprehensive_check_error_code(&compliance_result),
                    error_message: modular_compliance::get_comprehensive_check_error_message(&compliance_result),
                    failed_at: current_time,
                });
                
                return result
            };
        };
        
        // Perform the actual transfer (simplified for testing)
        // Update balances using helper function
        update_user_balance(registry, from, token_address, amount, false);
        update_user_balance(registry, to, token_address, amount, true);
        
        // Record transfer
        let transfer_id = registry.next_transfer_id;
        registry.next_transfer_id = registry.next_transfer_id + 1;
        
        let transfer_record = TransferRecord {
            transfer_id,
            from,
            to,
            amount,
            transfer_type: 1, // Regular transfer
            compliance_status: 1, // Passed
            timestamp: current_time,
        };
        
        // Add to user transfer history
        if (!table::contains(&registry.user_transfer_history, from)) {
            table::add(&mut registry.user_transfer_history, from, table::new());
        };
        let from_history = table::borrow_mut(&mut registry.user_transfer_history, from);
        table::add(from_history, transfer_id, transfer_record);
        
        if (!table::contains(&registry.user_transfer_history, to)) {
            table::add(&mut registry.user_transfer_history, to, table::new());
        };
        let to_history = table::borrow_mut(&mut registry.user_transfer_history, to);
        table::add(to_history, transfer_id, transfer_record);
        
        let result = TransferWithComplianceResult {
            success: true,
            error_code: 0,
            error_message: string::utf8(b"Transfer successful"),
            compliance_results: vector::empty(),
            transferred_at: current_time,
        };
        
        // Emit event
        event::emit_event(&mut registry.transfer_with_compliance_events, TransferWithComplianceEvent {
            token_address,
            from,
            to,
            amount,
            compliance_passed: true,
            transferred_at: current_time,
        });
        
        result
    }
    
    /// Force transfer tokens (compliance officer only)
    public fun force_transfer(
        account: &signer,
        token_address: address,
        from: address,
        to: address,
        amount: u64,
        transfer_reason: String
    ) acquires TRexTokenRegistry {
        let enforcer = signer::address_of(account);
        let registry = borrow_global_mut<TRexTokenRegistry>(enforcer);
        let current_time = timestamp::now_seconds();
        
        // Check if enforcer has force transfer permission
        assert!(token_roles::can_user_perform_action(token_address, enforcer, 1), constants::get_token_forced_transfer_not_authorized_error());
        
        // Check if token is T-REX compliant
        assert!(table::contains(&registry.trex_tokens, token_address), constants::get_compliance_module_not_found_error());
        
        let trex_config = table::borrow(&registry.trex_tokens, token_address);
        
        // Perform the forced transfer
        primary_fungible_store::transfer(
            account,
            trex_config.metadata,
            to,
            amount
        );
        
        // Record forced transfer
        let transfer_id = registry.next_transfer_id;
        registry.next_transfer_id = registry.next_transfer_id + 1;
        
        let transfer_record = TransferRecord {
            transfer_id,
            from,
            to,
            amount,
            transfer_type: 2, // Forced transfer
            compliance_status: 2, // Forced
            timestamp: current_time,
        };
        
        // Add to user transfer history
        if (!table::contains(&registry.user_transfer_history, from)) {
            table::add(&mut registry.user_transfer_history, from, table::new());
        };
        let from_history = table::borrow_mut(&mut registry.user_transfer_history, from);
        table::add(from_history, transfer_id, transfer_record);
        
        if (!table::contains(&registry.user_transfer_history, to)) {
            table::add(&mut registry.user_transfer_history, to, table::new());
        };
        let to_history = table::borrow_mut(&mut registry.user_transfer_history, to);
        table::add(to_history, transfer_id, transfer_record);
        
        // Update user balances
        update_user_balance(registry, from, token_address, amount, false);
        update_user_balance(registry, to, token_address, amount, true);
        
        // Emit event
        event::emit_event(&mut registry.forced_transfer_events, ForcedTransferEvent {
            token_address,
            from,
            to,
            amount,
            forced_by: enforcer,
            transfer_reason,
            transferred_at: current_time,
        });
    }

    // ========== TOKEN MANAGEMENT ==========
    
    /// Pause token
    public fun pause_token(
        account: &signer,
        token_address: address,
        pause_reason: String
    ) acquires TRexTokenRegistry {
        let pauser = signer::address_of(account);
        let registry = borrow_global_mut<TRexTokenRegistry>(pauser);
        let current_time = timestamp::now_seconds();
        
        // Check if pauser has pause permission
        assert!(token_roles::can_user_perform_action(token_address, pauser, 2), constants::get_access_control_not_authorized_error());
        
        // Pause token
        token_information::pause_token(account, token_address, pause_reason);
        
        // Emit event
        event::emit_event(&mut registry.token_paused_events, TokenPausedEvent {
            token_address,
            paused_by: pauser,
            pause_reason,
            paused_at: current_time,
        });
    }
    
    /// Unpause token
    public fun unpause_token(
        account: &signer,
        token_address: address
    ) acquires TRexTokenRegistry {
        let unpauser = signer::address_of(account);
        let registry = borrow_global_mut<TRexTokenRegistry>(unpauser);
        
        // Check if unpauser has pause permission
        assert!(token_roles::can_user_perform_action(token_address, unpauser, 2), constants::get_access_control_not_authorized_error());
        
        // Unpause token
        token_information::unpause_token(account, token_address);
    }

    // ========== VIEW FUNCTIONS ==========
    
    /// Check if token is T-REX compliant
    public fun is_trex_compliant(token_address: address): bool acquires TRexTokenRegistry {
        // Note: This function needs admin address to access registry
        // For now, we'll use a placeholder - this needs to be refactored
        let registry = borrow_global<TRexTokenRegistry>(@0x1);
        table::contains(&registry.trex_tokens, token_address)
    }
    
    /// Get T-REX token configuration
    public fun get_trex_token_config(token_address: address): (bool, bool, u8, u8, bool, bool, bool, u64, u64) acquires TRexTokenRegistry {
        // Note: This function needs admin address to access registry
        // For now, we'll use a placeholder - this needs to be refactored
        let registry = borrow_global<TRexTokenRegistry>(@0x1);
        assert!(table::contains(&registry.trex_tokens, token_address), constants::get_compliance_module_not_found_error());
        
        let config = table::borrow(&registry.trex_tokens, token_address);
        (
            config.compliance_enabled,
            config.identity_verification_required,
            config.required_kyc_level,
            config.required_investor_type,
            config.country_restrictions_enabled,
            config.transfer_restrictions_enabled,
            config.balance_restrictions_enabled,
            config.created_at,
            config.updated_at,
        )
    }
    
    /// Get user balance for token
    public fun get_user_balance(user: address, token_address: address): u64 acquires TRexTokenRegistry {
        // Note: This function needs admin address to access registry
        // For now, we'll use a placeholder - this needs to be refactored
        let registry = borrow_global<TRexTokenRegistry>(@0x1);
        
        if (!table::contains(&registry.user_balances, user)) {
            return 0
        };
        
        let user_balances = table::borrow(&registry.user_balances, user);
        if (!table::contains(user_balances, token_address)) {
            return 0
        };
        
        *table::borrow(user_balances, token_address)
    }
    
    /// Check if transfer result was successful
    public fun is_transfer_successful(result: &TransferWithComplianceResult): bool {
        result.success
    }
    
    /// DVP transfer function - allows external modules to perform transfers
    public fun dvp_transfer(
        from: address,
        to: address,
        token_address: address,
        amount: u64
    ) acquires TRexTokenRegistry {
        // Note: This function needs admin address to access registry
        // For now, we'll use a placeholder - this needs to be refactored
        let registry = borrow_global_mut<TRexTokenRegistry>(@0x1);
        
        // Check if token is T-REX compliant
        assert!(table::contains(&registry.trex_tokens, token_address), constants::get_compliance_module_not_found_error());
        
        // Update balances using helper function
        update_user_balance(registry, from, token_address, amount, false);
        update_user_balance(registry, to, token_address, amount, true);
        
        // Record transfer
        let current_time = timestamp::now_seconds();
        let transfer_id = registry.next_transfer_id;
        registry.next_transfer_id = registry.next_transfer_id + 1;
        
        let transfer_record = TransferRecord {
            transfer_id,
            from,
            to,
            amount,
            transfer_type: 3, // DVP transfer
            compliance_status: 1, // Passed
            timestamp: current_time,
        };
        
        // Add to user transfer history
        if (!table::contains(&registry.user_transfer_history, from)) {
            table::add(&mut registry.user_transfer_history, from, table::new());
        };
        let from_history = table::borrow_mut(&mut registry.user_transfer_history, from);
        table::add(from_history, transfer_id, transfer_record);
        
        if (!table::contains(&registry.user_transfer_history, to)) {
            table::add(&mut registry.user_transfer_history, to, table::new());
        };
        let to_history = table::borrow_mut(&mut registry.user_transfer_history, to);
        table::add(to_history, transfer_id, transfer_record);
        
        // Emit event
        event::emit_event(&mut registry.transfer_with_compliance_events, TransferWithComplianceEvent {
            token_address,
            from,
            to,
            amount,
            compliance_passed: true,
            transferred_at: current_time,
        });
    }
    
    /// Get user transfer history
    public fun get_user_transfer_history(user: address, token_address: address): vector<TransferRecord> acquires TRexTokenRegistry {
        let registry = borrow_global<TRexTokenRegistry>(user);
        let transfers = vector::empty();
        
        if (!table::contains(&registry.user_transfer_history, user)) {
            return transfers
        };
        
        let user_history = table::borrow(&registry.user_transfer_history, user);
        // Note: This is a simplified implementation
        // In a real implementation, you would filter by token_address
        
        transfers
    }
    
    /// Check if transfer is compliant
    public fun is_compliant_transfer(from: address, to: address, amount: u64): bool {
        // This is a simplified implementation
        // In a real implementation, you would perform actual compliance checks
        true
    }
    
    /// Get transfer restrictions for user
    public fun get_transfer_restrictions(user: address): vector<u8> {
        // This is a simplified implementation
        // In a real implementation, you would return actual transfer restrictions
        vector::empty()
    }

    // ========== HELPER FUNCTIONS ==========
    
    /// Update user balance
    public fun update_user_balance(
        registry: &mut TRexTokenRegistry,
        user: address,
        token_address: address,
        amount: u64,
        is_increase: bool
    ) {
        if (!table::contains(&registry.user_balances, user)) {
            table::add(&mut registry.user_balances, user, table::new());
        };
        
        let user_balances = table::borrow_mut(&mut registry.user_balances, user);
        
        if (!table::contains(user_balances, token_address)) {
            table::add(user_balances, token_address, 0);
        };
        
        let balance = table::borrow_mut(user_balances, token_address);
        if (is_increase) {
            *balance = *balance + amount;
        } else {
            *balance = *balance - amount;
        };
    }
}
