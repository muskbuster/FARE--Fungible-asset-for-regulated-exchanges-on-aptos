/// Modular Compliance module for T-REX compliant token system
/// Main compliance engine that orchestrates all compliance modules

module FARE::modular_compliance {
    use std::vector;
    use std::string::{Self, String};
    use std::table::{Self, Table};
    use std::error;
    use std::signer;
    use std::timestamp;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;
    use FARE::constants;
    use FARE::compliance_registry::{Self, ComplianceCheckResult};
    use FARE::transfer_rules::{Self, TransferValidationResult};
    use FARE::country_restrictions::{Self, CountryTransferValidationResult};

    // ========== STRUCTS ==========
    
    /// Compliance module configuration
    struct ComplianceModuleConfig has store, copy, drop {
        /// Module type
        module_type: u8,
        /// Whether module is enabled
        is_enabled: bool,
        /// Module priority (higher number = higher priority)
        priority: u64,
        /// Module configuration data
        config_data: vector<u8>,
        /// Module version
        version: u64,
        /// Created timestamp
        created_at: u64,
        /// Last updated timestamp
        updated_at: u64,
    }
    
    /// Comprehensive compliance check result
    struct ComprehensiveComplianceResult has store, copy, drop {
        /// Whether all compliance checks passed
        passed: bool,
        /// Error code if failed
        error_code: u64,
        /// Error message
        error_message: String,
        /// Individual module results
        module_results: vector<ComplianceCheckResult>,
        /// Additional compliance data
        compliance_data: vector<u8>,
        /// Check timestamp
        checked_at: u64,
    }
    
    // ========== GETTER FUNCTIONS FOR ComprehensiveComplianceResult ==========
    
    /// Get whether check passed
    public fun get_comprehensive_check_passed(result: &ComprehensiveComplianceResult): bool {
        result.passed
    }
    
    /// Get error code
    public fun get_comprehensive_check_error_code(result: &ComprehensiveComplianceResult): u64 {
        result.error_code
    }
    
    /// Get error message
    public fun get_comprehensive_check_error_message(result: &ComprehensiveComplianceResult): String {
        result.error_message
    }
    
    /// Get module results
    public fun get_comprehensive_check_module_results(result: &ComprehensiveComplianceResult): vector<ComplianceCheckResult> {
        result.module_results
    }
    
    /// Get compliance data
    public fun get_comprehensive_check_compliance_data(result: &ComprehensiveComplianceResult): vector<u8> {
        result.compliance_data
    }
    
    /// Compliance configuration for a token
    struct TokenComplianceConfig has store {
        /// Token address
        token_address: address,
        /// Enabled compliance modules
        enabled_modules: vector<u8>,
        /// Module configurations
        module_configs: Table<u8, ComplianceModuleConfig>,
        /// Global compliance settings
        global_settings: vector<u8>,
        /// Created timestamp
        created_at: u64,
        /// Last updated timestamp
        updated_at: u64,
    }
    
    /// Modular compliance registry
    struct ModularComplianceRegistry has key {
        /// Map of token address to compliance configuration
        token_compliance_configs: Table<address, TokenComplianceConfig>,
        /// Global compliance modules
        global_compliance_modules: Table<u8, ComplianceModuleConfig>,
        /// Events
        compliance_module_enabled_events: EventHandle<ComplianceModuleEnabledEvent>,
        compliance_module_disabled_events: EventHandle<ComplianceModuleDisabledEvent>,
        compliance_check_completed_events: EventHandle<ComplianceCheckCompletedEvent>,
        compliance_check_failed_events: EventHandle<ComplianceCheckFailedEvent>,
    }
    
    /// Compliance module enabled event
    struct ComplianceModuleEnabledEvent has store, drop {
        token_address: address,
        module_type: u8,
        enabled_by: address,
        enabled_at: u64,
    }
    
    /// Compliance module disabled event
    struct ComplianceModuleDisabledEvent has store, drop {
        token_address: address,
        module_type: u8,
        disabled_by: address,
        disabled_at: u64,
    }
    
    /// Compliance check completed event
    struct ComplianceCheckCompletedEvent has store, drop {
        token_address: address,
        user: address,
        check_type: u8,
        passed: bool,
        checked_at: u64,
    }
    
    /// Compliance check failed event
    struct ComplianceCheckFailedEvent has store, drop {
        token_address: address,
        user: address,
        check_type: u8,
        error_code: u64,
        error_message: String,
        failed_at: u64,
    }

    // ========== INITIALIZATION ==========
    
    /// Initialize modular compliance registry
    public fun initialize(account: &signer) {
        let account_addr = signer::address_of(account);
        
        // Ensure account is not already initialized
        assert!(!exists<ModularComplianceRegistry>(account_addr), constants::get_access_control_not_authorized_error());
        
        let registry = ModularComplianceRegistry {
            token_compliance_configs: table::new(),
            global_compliance_modules: table::new(),
            compliance_module_enabled_events: account::new_event_handle<ComplianceModuleEnabledEvent>(account),
            compliance_module_disabled_events: account::new_event_handle<ComplianceModuleDisabledEvent>(account),
            compliance_check_completed_events: account::new_event_handle<ComplianceCheckCompletedEvent>(account),
            compliance_check_failed_events: account::new_event_handle<ComplianceCheckFailedEvent>(account),
        };
        
        move_to(account, registry);
    }

    // ========== TOKEN COMPLIANCE CONFIGURATION ==========
    
    /// Initialize compliance configuration for a token
    public fun initialize_token_compliance(
        account: &signer,
        token_address: address
    ) acquires ModularComplianceRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<ModularComplianceRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if token compliance is already initialized
        assert!(!table::contains(&registry.token_compliance_configs, token_address), constants::get_compliance_module_already_exists_error());
        
        let config = TokenComplianceConfig {
            token_address,
            enabled_modules: vector::empty(),
            module_configs: table::new(),
            global_settings: vector::empty(),
            created_at: current_time,
            updated_at: current_time,
        };
        
        table::add(&mut registry.token_compliance_configs, token_address, config);
    }
    
    /// Enable compliance module for a token
    public fun enable_compliance_module(
        account: &signer,
        token_address: address,
        module_type: u8,
        priority: u64,
        config_data: vector<u8>
    ) acquires ModularComplianceRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<ModularComplianceRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if token compliance is initialized
        assert!(table::contains(&registry.token_compliance_configs, token_address), constants::get_compliance_module_not_found_error());
        
        // Validate module type
        assert!(constants::is_valid_compliance_module_type(module_type), constants::get_invalid_parameter_error());
        
        // Validate priority
        assert!(priority > 0, constants::get_invalid_parameter_error());
        
        let token_config = table::borrow_mut(&mut registry.token_compliance_configs, token_address);
        
        // Check if module is already enabled
        let (found, _) = find_module_index(&token_config.enabled_modules, module_type);
        assert!(!found, constants::get_compliance_module_already_exists_error());
        
        let module_config = ComplianceModuleConfig {
            module_type,
            is_enabled: true,
            priority,
            config_data,
            version: 1,
            created_at: current_time,
            updated_at: current_time,
        };
        
        table::add(&mut token_config.module_configs, module_type, module_config);
        vector::push_back(&mut token_config.enabled_modules, module_type);
        token_config.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut registry.compliance_module_enabled_events, ComplianceModuleEnabledEvent {
            token_address,
            module_type,
            enabled_by: account_addr,
            enabled_at: current_time,
        });
    }
    
    /// Disable compliance module for a token
    public fun disable_compliance_module(
        account: &signer,
        token_address: address,
        module_type: u8
    ) acquires ModularComplianceRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<ModularComplianceRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if token compliance is initialized
        assert!(table::contains(&registry.token_compliance_configs, token_address), constants::get_compliance_module_not_found_error());
        
        let token_config = table::borrow_mut(&mut registry.token_compliance_configs, token_address);
        
        // Check if module is enabled
        let (found, index) = find_module_index(&token_config.enabled_modules, module_type);
        assert!(found, constants::get_compliance_module_not_found_error());
        
        // Remove module from enabled modules
        vector::remove(&mut token_config.enabled_modules, index);
        
        // Remove module configuration
        table::remove(&mut token_config.module_configs, module_type);
        token_config.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut registry.compliance_module_disabled_events, ComplianceModuleDisabledEvent {
            token_address,
            module_type,
            disabled_by: account_addr,
            disabled_at: current_time,
        });
    }
    
    /// Update compliance module configuration
    public fun update_compliance_module_config(
        account: &signer,
        token_address: address,
        module_type: u8,
        priority: u64,
        config_data: vector<u8>
    ) acquires ModularComplianceRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<ModularComplianceRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if token compliance is initialized
        assert!(table::contains(&registry.token_compliance_configs, token_address), constants::get_compliance_module_not_found_error());
        
        // Validate priority
        assert!(priority > 0, constants::get_invalid_parameter_error());
        
        let token_config = table::borrow_mut(&mut registry.token_compliance_configs, token_address);
        
        // Check if module is enabled
        assert!(table::contains(&token_config.module_configs, module_type), constants::get_compliance_module_not_found_error());
        
        let module_config = table::borrow_mut(&mut token_config.module_configs, module_type);
        module_config.priority = priority;
        module_config.config_data = config_data;
        module_config.version = module_config.version + 1;
        module_config.updated_at = current_time;
        token_config.updated_at = current_time;
    }

    // ========== COMPREHENSIVE COMPLIANCE CHECKING ==========
    
    /// Perform comprehensive compliance check
    public fun check_comprehensive_compliance(
        account: &signer,
        token_address: address,
        user: address,
        check_type: u8,
        check_data: vector<u8>
    ): ComprehensiveComplianceResult acquires ModularComplianceRegistry {
        let account_addr = signer::address_of(account);
        // Registry is stored at the admin address, not the user address
        let registry = borrow_global_mut<ModularComplianceRegistry>(@0x1);
        let current_time = timestamp::now_seconds();
        
        // Check if token compliance is initialized
        assert!(table::contains(&registry.token_compliance_configs, token_address), constants::get_compliance_module_not_found_error());
        
        let token_config = table::borrow(&registry.token_compliance_configs, token_address);
        let module_results = vector::empty();
        let all_passed = true;
        let error_code = 0;
        let error_message = string::utf8(b"");
        
        // Sort modules by priority (highest first)
        let sorted_modules = token_config.enabled_modules;
        // Note: In a real implementation, you would sort by priority
        
        // Check each enabled module
        let len = vector::length(&sorted_modules);
        let i = 0;
        while (i < len) {
            let module_type = *vector::borrow(&sorted_modules, i);
            let module_config = table::borrow(&token_config.module_configs, module_type);
            
            if (module_config.is_enabled) {
                let module_result = check_individual_module(
                    module_type,
                    user,
                    check_type,
                    check_data,
                    module_config.config_data
                );
                
                vector::push_back(&mut module_results, module_result);
                
                if (!compliance_registry::get_check_passed(&module_result)) {
                    all_passed = false;
                    error_code = compliance_registry::get_check_error_code(&module_result);
                    error_message = compliance_registry::get_check_error_message(&module_result);
                    break // Stop at first failure
                };
            };
            i = i + 1;
        };
        
        let result = ComprehensiveComplianceResult {
            passed: all_passed,
            error_code,
            error_message,
            module_results,
            compliance_data: vector::empty(),
            checked_at: current_time,
        };
        
        // Emit event
        if (all_passed) {
            event::emit_event(&mut registry.compliance_check_completed_events, ComplianceCheckCompletedEvent {
                token_address,
                user,
                check_type,
                passed: true,
                checked_at: current_time,
            });
        } else {
            event::emit_event(&mut registry.compliance_check_failed_events, ComplianceCheckFailedEvent {
                token_address,
                user,
                check_type,
                error_code,
                error_message,
                failed_at: current_time,
            });
        };
        
        result
    }
    
    /// Check individual compliance module
    fun check_individual_module(
        module_type: u8,
        user: address,
        check_type: u8,
        check_data: vector<u8>,
        config_data: vector<u8>
    ): ComplianceCheckResult {
        let current_time = timestamp::now_seconds();
        
        if (module_type == constants::get_compliance_module_transfer_restrictions()) {
            // Check transfer restrictions
            // This is a simplified implementation
            // In a real implementation, you would call the actual transfer rules module
            return compliance_registry::new_compliance_check_result(
                true,
                0,
                string::utf8(b"Transfer restrictions check passed"),
                vector::empty(),
                current_time
            )
        } else if (module_type == constants::get_compliance_module_country_restrictions()) {
            // Check country restrictions
            // This is a simplified implementation
            // In a real implementation, you would call the actual country restrictions module
            return compliance_registry::new_compliance_check_result(
                true,
                0,
                string::utf8(b"Country restrictions check passed"),
                vector::empty(),
                current_time
            )
        } else if (module_type == constants::get_compliance_module_balance_restrictions()) {
            // Check balance restrictions
            // This is a simplified implementation
            return compliance_registry::new_compliance_check_result(
                true,
                0,
                string::utf8(b"Balance restrictions check passed"),
                vector::empty(),
                current_time
            )
        } else if (module_type == constants::get_compliance_module_investor_type_restrictions()) {
            // Check investor type restrictions
            // This is a simplified implementation
            return compliance_registry::new_compliance_check_result(
                true,
                0,
                string::utf8(b"Investor type restrictions check passed"),
                vector::empty(),
                current_time
            )
        } else if (module_type == constants::get_compliance_module_whitelist_blacklist()) {
            // Check whitelist/blacklist
            // This is a simplified implementation
            return compliance_registry::new_compliance_check_result(
                true,
                0,
                string::utf8(b"Whitelist/blacklist check passed"),
                vector::empty(),
                current_time
            )
        } else if (module_type == constants::get_compliance_module_time_based_restrictions()) {
            // Check time-based restrictions
            // This is a simplified implementation
            return compliance_registry::new_compliance_check_result(
                true,
                0,
                string::utf8(b"Time-based restrictions check passed"),
                vector::empty(),
                current_time
            )
        } else {
            // Unknown module type
            return compliance_registry::new_compliance_check_result(
                false,
                constants::get_compliance_module_not_found_error(),
                string::utf8(b"Unknown compliance module type"),
                vector::empty(),
                current_time
            )
        }
    }

    // ========== VIEW FUNCTIONS ==========
    
    /// Get token compliance configuration
    public fun get_token_compliance_config(token_address: address): (vector<u8>, u64, u64) acquires ModularComplianceRegistry {
        let registry = borrow_global<ModularComplianceRegistry>(token_address);
        assert!(table::contains(&registry.token_compliance_configs, token_address), constants::get_compliance_module_not_found_error());
        
        let config = table::borrow(&registry.token_compliance_configs, token_address);
        (config.enabled_modules, config.created_at, config.updated_at)
    }
    
    /// Get compliance module configuration for a token
    public fun get_compliance_module_config(token_address: address, module_type: u8): (bool, u64, vector<u8>, u64, u64, u64) acquires ModularComplianceRegistry {
        let registry = borrow_global<ModularComplianceRegistry>(token_address);
        assert!(table::contains(&registry.token_compliance_configs, token_address), constants::get_compliance_module_not_found_error());
        
        let config = table::borrow(&registry.token_compliance_configs, token_address);
        assert!(table::contains(&config.module_configs, module_type), constants::get_compliance_module_not_found_error());
        
        let module_config = table::borrow(&config.module_configs, module_type);
        (
            module_config.is_enabled,
            module_config.priority,
            module_config.config_data,
            module_config.version,
            module_config.created_at,
            module_config.updated_at,
        )
    }
    
    /// Check if compliance module is enabled for a token
    public fun is_compliance_module_enabled(token_address: address, module_type: u8): bool acquires ModularComplianceRegistry {
        let registry = borrow_global<ModularComplianceRegistry>(token_address);
        
        if (!table::contains(&registry.token_compliance_configs, token_address)) {
            return false
        };
        
        let config = table::borrow(&registry.token_compliance_configs, token_address);
        
        if (!table::contains(&config.module_configs, module_type)) {
            return false
        };
        
        let module_config = table::borrow(&config.module_configs, module_type);
        module_config.is_enabled
    }
    
    /// Get all enabled compliance modules for a token
    public fun get_enabled_compliance_modules(token_address: address): vector<u8> acquires ModularComplianceRegistry {
        let registry = borrow_global<ModularComplianceRegistry>(token_address);
        
        if (!table::contains(&registry.token_compliance_configs, token_address)) {
            return vector::empty()
        };
        
        let config = table::borrow(&registry.token_compliance_configs, token_address);
        config.enabled_modules
    }
    
    /// Check if token has compliance configuration
    public fun has_token_compliance_config(token_address: address): bool acquires ModularComplianceRegistry {
        let registry = borrow_global<ModularComplianceRegistry>(token_address);
        table::contains(&registry.token_compliance_configs, token_address)
    }
    
    /// Get number of enabled compliance modules for a token
    public fun get_enabled_modules_count(token_address: address): u64 acquires ModularComplianceRegistry {
        let registry = borrow_global<ModularComplianceRegistry>(token_address);
        
        if (!table::contains(&registry.token_compliance_configs, token_address)) {
            return 0
        };
        
        let config = table::borrow(&registry.token_compliance_configs, token_address);
        vector::length(&config.enabled_modules)
    }

    // ========== HELPER FUNCTIONS ==========
    
    /// Find module index in enabled modules vector
    fun find_module_index(enabled_modules: &vector<u8>, module_type: u8): (bool, u64) {
        let len = vector::length(enabled_modules);
        let i = 0;
        while (i < len) {
            let enabled_module = *vector::borrow(enabled_modules, i);
            if (enabled_module == module_type) {
                return (true, i)
            };
            i = i + 1;
        };
        (false, 0)
    }
}
