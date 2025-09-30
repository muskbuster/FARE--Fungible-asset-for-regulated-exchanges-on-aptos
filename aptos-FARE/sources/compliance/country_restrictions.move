/// Country Restrictions module for T-REX compliant token system
/// Implements country-based transfer restrictions and validation

module FARE::country_restrictions {
    use std::vector;
    use std::string::{Self, String};
    use std::table::{Self, Table};
    use std::error;
    use std::signer;
    use std::timestamp;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;
    use FARE::constants;

    // ========== STRUCTS ==========
    
    /// Country restriction configuration
    struct CountryRestriction has store, copy, drop {
        /// Country code (ISO 3166-1 alpha-2)
        country_code: vector<u8>,
        /// Whether country is blocked
        is_blocked: bool,
        /// Whether country is whitelisted
        is_whitelisted: bool,
        /// Maximum transfer amount for this country
        max_transfer_amount: u64,
        /// Daily transfer limit for this country
        daily_transfer_limit: u64,
        /// Monthly transfer limit for this country
        monthly_transfer_limit: u64,
        /// Whether transfers to this country require approval
        requires_approval: bool,
        /// Restriction reason
        restriction_reason: String,
        /// Created timestamp
        created_at: u64,
        /// Last updated timestamp
        updated_at: u64,
    }
    
    /// Bilateral transfer restriction between two countries
    struct BilateralRestriction has store, copy, drop {
        /// Source country code
        source_country: vector<u8>,
        /// Destination country code
        destination_country: vector<u8>,
        /// Whether transfer is blocked
        is_blocked: bool,
        /// Maximum transfer amount
        max_transfer_amount: u64,
        /// Whether transfer requires approval
        requires_approval: bool,
        /// Restriction reason
        restriction_reason: String,
        /// Created timestamp
        created_at: u64,
        /// Last updated timestamp
        updated_at: u64,
    }
    
    /// Jurisdiction-based transfer rule
    struct JurisdictionRule has store, copy, drop {
        /// Jurisdiction identifier
        jurisdiction_id: String,
        /// Country codes in this jurisdiction
        country_codes: vector<vector<u8>>,
        /// Transfer rules for this jurisdiction
        transfer_rules: vector<u8>,
        /// Whether jurisdiction is active
        is_active: bool,
        /// Created timestamp
        created_at: u64,
        /// Last updated timestamp
        updated_at: u64,
    }
    
    /// Country transfer validation result
    struct CountryTransferValidationResult has store, copy, drop {
        /// Whether transfer is valid
        is_valid: bool,
        /// Error code if invalid
        error_code: u64,
        /// Error message
        error_message: String,
        /// Additional validation data
        validation_data: vector<u8>,
        /// Validation timestamp
        validated_at: u64,
    }
    
    /// Country restrictions registry
    struct CountryRestrictionsRegistry has key {
        /// Map of country code to country restriction
        country_restrictions: Table<vector<u8>, CountryRestriction>,
        /// Map of bilateral restriction key to bilateral restriction
        bilateral_restrictions: Table<String, BilateralRestriction>,
        /// Map of jurisdiction ID to jurisdiction rule
        jurisdiction_rules: Table<String, JurisdictionRule>,
        /// Global country restrictions enabled
        global_restrictions_enabled: bool,
        /// Default transfer amount limit
        default_transfer_limit: u64,
        /// Events
        country_restriction_updated_events: EventHandle<CountryRestrictionUpdatedEvent>,
        bilateral_restriction_updated_events: EventHandle<BilateralRestrictionUpdatedEvent>,
        jurisdiction_rule_updated_events: EventHandle<JurisdictionRuleUpdatedEvent>,
        country_transfer_validated_events: EventHandle<CountryTransferValidatedEvent>,
        country_transfer_blocked_events: EventHandle<CountryTransferBlockedEvent>,
    }
    
    /// Country restriction updated event
    struct CountryRestrictionUpdatedEvent has store, drop {
        country_code: vector<u8>,
        is_blocked: bool,
        is_whitelisted: bool,
        updated_by: address,
        updated_at: u64,
    }
    
    /// Bilateral restriction updated event
    struct BilateralRestrictionUpdatedEvent has store, drop {
        source_country: vector<u8>,
        destination_country: vector<u8>,
        is_blocked: bool,
        updated_by: address,
        updated_at: u64,
    }
    
    /// Jurisdiction rule updated event
    struct JurisdictionRuleUpdatedEvent has store, drop {
        jurisdiction_id: String,
        updated_by: address,
        updated_at: u64,
    }
    
    /// Country transfer validated event
    struct CountryTransferValidatedEvent has store, drop {
        source_country: vector<u8>,
        destination_country: vector<u8>,
        amount: u64,
        is_valid: bool,
        validated_at: u64,
    }
    
    /// Country transfer blocked event
    struct CountryTransferBlockedEvent has store, drop {
        source_country: vector<u8>,
        destination_country: vector<u8>,
        amount: u64,
        reason: String,
        blocked_at: u64,
    }

    // ========== INITIALIZATION ==========
    
    /// Initialize country restrictions registry
    public fun initialize(account: &signer) {
        let account_addr = signer::address_of(account);
        
        // Ensure account is not already initialized
        assert!(!exists<CountryRestrictionsRegistry>(account_addr), constants::get_access_control_not_authorized_error());
        
        let registry = CountryRestrictionsRegistry {
            country_restrictions: table::new(),
            bilateral_restrictions: table::new(),
            jurisdiction_rules: table::new(),
            global_restrictions_enabled: true,
            default_transfer_limit: constants::get_max_transfer_amount(),
            country_restriction_updated_events: account::new_event_handle<CountryRestrictionUpdatedEvent>(account),
            bilateral_restriction_updated_events: account::new_event_handle<BilateralRestrictionUpdatedEvent>(account),
            jurisdiction_rule_updated_events: account::new_event_handle<JurisdictionRuleUpdatedEvent>(account),
            country_transfer_validated_events: account::new_event_handle<CountryTransferValidatedEvent>(account),
            country_transfer_blocked_events: account::new_event_handle<CountryTransferBlockedEvent>(account),
        };
        
        move_to(account, registry);
    }

    // ========== COUNTRY RESTRICTIONS MANAGEMENT ==========
    
    /// Add or update country restriction
    public fun set_country_restriction(
        account: &signer,
        country_code: vector<u8>,
        is_blocked: bool,
        is_whitelisted: bool,
        max_transfer_amount: u64,
        daily_transfer_limit: u64,
        monthly_transfer_limit: u64,
        requires_approval: bool,
        restriction_reason: String
    ) acquires CountryRestrictionsRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<CountryRestrictionsRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Validate country code
        assert!(constants::is_valid_country_code(country_code), constants::get_invalid_country_code_error());
        
        // Validate parameters
        assert!(constants::is_valid_amount(max_transfer_amount), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_amount(daily_transfer_limit), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_amount(monthly_transfer_limit), constants::get_invalid_parameter_error());
        
        let restriction = CountryRestriction {
            country_code,
            is_blocked,
            is_whitelisted,
            max_transfer_amount,
            daily_transfer_limit,
            monthly_transfer_limit,
            requires_approval,
            restriction_reason,
            created_at: current_time,
            updated_at: current_time,
        };
        
        table::add(&mut registry.country_restrictions, country_code, restriction);
        
        // Emit event
        event::emit_event(&mut registry.country_restriction_updated_events, CountryRestrictionUpdatedEvent {
            country_code,
            is_blocked,
            is_whitelisted,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }
    
    /// Remove country restriction
    public fun remove_country_restriction(
        account: &signer,
        country_code: vector<u8>
    ) acquires CountryRestrictionsRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<CountryRestrictionsRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if country restriction exists
        assert!(table::contains(&registry.country_restrictions, country_code), constants::get_compliance_module_not_found_error());
        
        table::remove(&mut registry.country_restrictions, country_code);
        
        // Emit event
        event::emit_event(&mut registry.country_restriction_updated_events, CountryRestrictionUpdatedEvent {
            country_code,
            is_blocked: false,
            is_whitelisted: false,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }
    
    /// Block a country
    public fun block_country(
        account: &signer,
        country_code: vector<u8>,
        restriction_reason: String
    ) acquires CountryRestrictionsRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<CountryRestrictionsRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Validate country code
        assert!(constants::is_valid_country_code(country_code), constants::get_invalid_country_code_error());
        
        if (table::contains(&registry.country_restrictions, country_code)) {
            let restriction = table::borrow_mut(&mut registry.country_restrictions, country_code);
            restriction.is_blocked = true;
            restriction.restriction_reason = restriction_reason;
            restriction.updated_at = current_time;
        } else {
            let restriction = CountryRestriction {
                country_code,
                is_blocked: true,
                is_whitelisted: false,
                max_transfer_amount: 0,
                daily_transfer_limit: 0,
                monthly_transfer_limit: 0,
                requires_approval: true,
                restriction_reason,
                created_at: current_time,
                updated_at: current_time,
            };
            table::add(&mut registry.country_restrictions, country_code, restriction);
        };
        
        // Emit event
        event::emit_event(&mut registry.country_restriction_updated_events, CountryRestrictionUpdatedEvent {
            country_code,
            is_blocked: true,
            is_whitelisted: false,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }
    
    /// Unblock a country
    public fun unblock_country(
        account: &signer,
        country_code: vector<u8>
    ) acquires CountryRestrictionsRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<CountryRestrictionsRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if country restriction exists
        assert!(table::contains(&registry.country_restrictions, country_code), constants::get_compliance_module_not_found_error());
        
        let restriction = table::borrow_mut(&mut registry.country_restrictions, country_code);
        restriction.is_blocked = false;
        restriction.restriction_reason = string::utf8(b"");
        restriction.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut registry.country_restriction_updated_events, CountryRestrictionUpdatedEvent {
            country_code,
            is_blocked: false,
            is_whitelisted: restriction.is_whitelisted,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }

    // ========== BILATERAL RESTRICTIONS MANAGEMENT ==========
    
    /// Add or update bilateral restriction
    public fun set_bilateral_restriction(
        account: &signer,
        source_country: vector<u8>,
        destination_country: vector<u8>,
        is_blocked: bool,
        max_transfer_amount: u64,
        requires_approval: bool,
        restriction_reason: String
    ) acquires CountryRestrictionsRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<CountryRestrictionsRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Validate country codes
        assert!(constants::is_valid_country_code(source_country), constants::get_invalid_country_code_error());
        assert!(constants::is_valid_country_code(destination_country), constants::get_invalid_country_code_error());
        
        // Validate parameters
        assert!(constants::is_valid_amount(max_transfer_amount), constants::get_invalid_parameter_error());
        
        let restriction_key = create_bilateral_key(source_country, destination_country);
        
        let restriction = BilateralRestriction {
            source_country,
            destination_country,
            is_blocked,
            max_transfer_amount,
            requires_approval,
            restriction_reason,
            created_at: current_time,
            updated_at: current_time,
        };
        
        table::add(&mut registry.bilateral_restrictions, restriction_key, restriction);
        
        // Emit event
        event::emit_event(&mut registry.bilateral_restriction_updated_events, BilateralRestrictionUpdatedEvent {
            source_country,
            destination_country,
            is_blocked,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }
    
    /// Remove bilateral restriction
    public fun remove_bilateral_restriction(
        account: &signer,
        source_country: vector<u8>,
        destination_country: vector<u8>
    ) acquires CountryRestrictionsRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<CountryRestrictionsRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        let restriction_key = create_bilateral_key(source_country, destination_country);
        
        // Check if bilateral restriction exists
        assert!(table::contains(&registry.bilateral_restrictions, restriction_key), constants::get_compliance_module_not_found_error());
        
        table::remove(&mut registry.bilateral_restrictions, restriction_key);
        
        // Emit event
        event::emit_event(&mut registry.bilateral_restriction_updated_events, BilateralRestrictionUpdatedEvent {
            source_country,
            destination_country,
            is_blocked: false,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }

    // ========== JURISDICTION RULES MANAGEMENT ==========
    
    /// Add or update jurisdiction rule
    public fun set_jurisdiction_rule(
        account: &signer,
        jurisdiction_id: String,
        country_codes: vector<vector<u8>>,
        transfer_rules: vector<u8>,
        is_active: bool
    ) acquires CountryRestrictionsRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<CountryRestrictionsRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Validate country codes
        let len = vector::length(&country_codes);
        let i = 0;
        while (i < len) {
            let country_code = *vector::borrow(&country_codes, i);
            assert!(constants::is_valid_country_code(country_code), constants::get_invalid_country_code_error());
            i = i + 1;
        };
        
        let rule = JurisdictionRule {
            jurisdiction_id,
            country_codes,
            transfer_rules,
            is_active,
            created_at: current_time,
            updated_at: current_time,
        };
        
        table::add(&mut registry.jurisdiction_rules, jurisdiction_id, rule);
        
        // Emit event
        event::emit_event(&mut registry.jurisdiction_rule_updated_events, JurisdictionRuleUpdatedEvent {
            jurisdiction_id,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }
    
    /// Remove jurisdiction rule
    public fun remove_jurisdiction_rule(
        account: &signer,
        jurisdiction_id: String
    ) acquires CountryRestrictionsRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<CountryRestrictionsRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if jurisdiction rule exists
        assert!(table::contains(&registry.jurisdiction_rules, jurisdiction_id), constants::get_compliance_module_not_found_error());
        
        table::remove(&mut registry.jurisdiction_rules, jurisdiction_id);
        
        // Emit event
        event::emit_event(&mut registry.jurisdiction_rule_updated_events, JurisdictionRuleUpdatedEvent {
            jurisdiction_id,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }

    // ========== TRANSFER VALIDATION ==========
    
    /// Validate country transfer
    public fun validate_country_transfer(
        account: &signer,
        source_country: vector<u8>,
        destination_country: vector<u8>,
        amount: u64
    ): CountryTransferValidationResult acquires CountryRestrictionsRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<CountryRestrictionsRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Validate country codes
        assert!(constants::is_valid_country_code(source_country), constants::get_invalid_country_code_error());
        assert!(constants::is_valid_country_code(destination_country), constants::get_invalid_country_code_error());
        
        // Validate amount
        if (!constants::is_valid_amount(amount)) {
            let result = CountryTransferValidationResult {
                is_valid: false,
                error_code: constants::get_invalid_amount_error(),
                error_message: string::utf8(b"Invalid transfer amount"),
                validation_data: vector::empty(),
                validated_at: current_time,
            };
            
            // Emit event
            event::emit_event(&mut registry.country_transfer_blocked_events, CountryTransferBlockedEvent {
                source_country,
                destination_country,
                amount,
                reason: string::utf8(b"Invalid transfer amount"),
                blocked_at: current_time,
            });
            
            return result
        };
        
        // Check if global restrictions are enabled
        if (!registry.global_restrictions_enabled) {
            let result = CountryTransferValidationResult {
                is_valid: true,
                error_code: 0,
                error_message: string::utf8(b"Transfer is valid"),
                validation_data: vector::empty(),
                validated_at: current_time,
            };
            
            // Emit event
            event::emit_event(&mut registry.country_transfer_validated_events, CountryTransferValidatedEvent {
                source_country,
                destination_country,
                amount,
                is_valid: true,
                validated_at: current_time,
            });
            
            return result
        };
        
        // Check if source country is blocked
        if (table::contains(&registry.country_restrictions, source_country)) {
            let restriction = table::borrow(&registry.country_restrictions, source_country);
            if (restriction.is_blocked) {
                let result = CountryTransferValidationResult {
                    is_valid: false,
                    error_code: constants::get_compliance_country_blocked_error(),
                    error_message: string::utf8(b"Source country is blocked"),
                    validation_data: vector::empty(),
                    validated_at: current_time,
                };
                
                // Emit event
                event::emit_event(&mut registry.country_transfer_blocked_events, CountryTransferBlockedEvent {
                    source_country,
                    destination_country,
                    amount,
                    reason: string::utf8(b"Source country is blocked"),
                    blocked_at: current_time,
                });
                
                return result
            };
        };
        
        // Check if destination country is blocked
        if (table::contains(&registry.country_restrictions, destination_country)) {
            let restriction = table::borrow(&registry.country_restrictions, destination_country);
            if (restriction.is_blocked) {
                let result = CountryTransferValidationResult {
                    is_valid: false,
                    error_code: constants::get_compliance_country_blocked_error(),
                    error_message: string::utf8(b"Destination country is blocked"),
                    validation_data: vector::empty(),
                    validated_at: current_time,
                };
                
                // Emit event
                event::emit_event(&mut registry.country_transfer_blocked_events, CountryTransferBlockedEvent {
                    source_country,
                    destination_country,
                    amount,
                    reason: string::utf8(b"Destination country is blocked"),
                    blocked_at: current_time,
                });
                
                return result
            };
        };
        
        // Check bilateral restrictions
        let restriction_key = create_bilateral_key(source_country, destination_country);
        if (table::contains(&registry.bilateral_restrictions, restriction_key)) {
            let restriction = table::borrow(&registry.bilateral_restrictions, restriction_key);
            if (restriction.is_blocked) {
                let result = CountryTransferValidationResult {
                    is_valid: false,
                    error_code: constants::get_compliance_country_blocked_error(),
                    error_message: string::utf8(b"Bilateral transfer is blocked"),
                    validation_data: vector::empty(),
                    validated_at: current_time,
                };
                
                // Emit event
                event::emit_event(&mut registry.country_transfer_blocked_events, CountryTransferBlockedEvent {
                    source_country,
                    destination_country,
                    amount,
                    reason: string::utf8(b"Bilateral transfer is blocked"),
                    blocked_at: current_time,
                });
                
                return result
            };
            
            // Check bilateral transfer amount limit
            if (amount > restriction.max_transfer_amount) {
                let result = CountryTransferValidationResult {
                    is_valid: false,
                    error_code: constants::get_compliance_transfer_restricted_error(),
                    error_message: string::utf8(b"Transfer amount exceeds bilateral limit"),
                    validation_data: vector::empty(),
                    validated_at: current_time,
                };
                
                // Emit event
                event::emit_event(&mut registry.country_transfer_blocked_events, CountryTransferBlockedEvent {
                    source_country,
                    destination_country,
                    amount,
                    reason: string::utf8(b"Transfer amount exceeds bilateral limit"),
                    blocked_at: current_time,
                });
                
                return result
            };
        };
        
        // Check country-specific restrictions
        if (table::contains(&registry.country_restrictions, destination_country)) {
            let restriction = table::borrow(&registry.country_restrictions, destination_country);
            if (amount > restriction.max_transfer_amount) {
                let result = CountryTransferValidationResult {
                    is_valid: false,
                    error_code: constants::get_compliance_transfer_restricted_error(),
                    error_message: string::utf8(b"Transfer amount exceeds country limit"),
                    validation_data: vector::empty(),
                    validated_at: current_time,
                };
                
                // Emit event
                event::emit_event(&mut registry.country_transfer_blocked_events, CountryTransferBlockedEvent {
                    source_country,
                    destination_country,
                    amount,
                    reason: string::utf8(b"Transfer amount exceeds country limit"),
                    blocked_at: current_time,
                });
                
                return result
            };
        };
        
        // Transfer is valid
        let result = CountryTransferValidationResult {
            is_valid: true,
            error_code: 0,
            error_message: string::utf8(b"Transfer is valid"),
            validation_data: vector::empty(),
            validated_at: current_time,
        };
        
        // Emit event
        event::emit_event(&mut registry.country_transfer_validated_events, CountryTransferValidatedEvent {
            source_country,
            destination_country,
            amount,
            is_valid: true,
            validated_at: current_time,
        });
        
        result
    }

    // ========== VIEW FUNCTIONS ==========
    
    /// Get country restriction information
    public fun get_country_restriction(country_code: vector<u8>): (bool, bool, u64, u64, u64, bool, String, u64, u64) acquires CountryRestrictionsRegistry {
        let registry = borrow_global<CountryRestrictionsRegistry>(@0x0); // This will need to be updated with actual address
        assert!(table::contains(&registry.country_restrictions, country_code), constants::get_compliance_module_not_found_error());
        
        let restriction = table::borrow(&registry.country_restrictions, country_code);
        (
            restriction.is_blocked,
            restriction.is_whitelisted,
            restriction.max_transfer_amount,
            restriction.daily_transfer_limit,
            restriction.monthly_transfer_limit,
            restriction.requires_approval,
            restriction.restriction_reason,
            restriction.created_at,
            restriction.updated_at,
        )
    }
    
    /// Get bilateral restriction information
    public fun get_bilateral_restriction(source_country: vector<u8>, destination_country: vector<u8>): (bool, u64, bool, String, u64, u64) acquires CountryRestrictionsRegistry {
        let registry = borrow_global<CountryRestrictionsRegistry>(@0x0); // This will need to be updated with actual address
        let restriction_key = create_bilateral_key(source_country, destination_country);
        assert!(table::contains(&registry.bilateral_restrictions, restriction_key), constants::get_compliance_module_not_found_error());
        
        let restriction = table::borrow(&registry.bilateral_restrictions, restriction_key);
        (
            restriction.is_blocked,
            restriction.max_transfer_amount,
            restriction.requires_approval,
            restriction.restriction_reason,
            restriction.created_at,
            restriction.updated_at,
        )
    }
    
    /// Get jurisdiction rule information
    public fun get_jurisdiction_rule(jurisdiction_id: String): (vector<vector<u8>>, vector<u8>, bool, u64, u64) acquires CountryRestrictionsRegistry {
        let registry = borrow_global<CountryRestrictionsRegistry>(@0x0); // This will need to be updated with actual address
        assert!(table::contains(&registry.jurisdiction_rules, jurisdiction_id), constants::get_compliance_module_not_found_error());
        
        let rule = table::borrow(&registry.jurisdiction_rules, jurisdiction_id);
        (
            rule.country_codes,
            rule.transfer_rules,
            rule.is_active,
            rule.created_at,
            rule.updated_at,
        )
    }
    
    /// Check if country is blocked (internal function without acquires)
    fun is_country_blocked_internal(registry: &CountryRestrictionsRegistry, country_code: vector<u8>): bool {
        if (!table::contains(&registry.country_restrictions, country_code)) {
            return false
        };
        
        let restriction = table::borrow(&registry.country_restrictions, country_code);
        restriction.is_blocked
    }
    
    /// Check if country is blocked
    public fun is_country_blocked(country_code: vector<u8>): bool acquires CountryRestrictionsRegistry {
        let registry = borrow_global<CountryRestrictionsRegistry>(@0x0); // This will need to be updated with actual address
        is_country_blocked_internal(registry, country_code)
    }
    
    /// Check if country is whitelisted
    public fun is_country_whitelisted(country_code: vector<u8>): bool acquires CountryRestrictionsRegistry {
        let registry = borrow_global<CountryRestrictionsRegistry>(@0x0); // This will need to be updated with actual address
        
        if (!table::contains(&registry.country_restrictions, country_code)) {
            return false
        };
        
        let restriction = table::borrow(&registry.country_restrictions, country_code);
        restriction.is_whitelisted
    }
    
    /// Check if bilateral transfer is blocked (internal function without acquires)
    fun is_bilateral_transfer_blocked_internal(registry: &CountryRestrictionsRegistry, source_country: vector<u8>, destination_country: vector<u8>): bool {
        let restriction_key = create_bilateral_key(source_country, destination_country);
        
        if (!table::contains(&registry.bilateral_restrictions, restriction_key)) {
            return false
        };
        
        let restriction = table::borrow(&registry.bilateral_restrictions, restriction_key);
        restriction.is_blocked
    }
    
    /// Check if bilateral transfer is blocked
    public fun is_bilateral_transfer_blocked(source_country: vector<u8>, destination_country: vector<u8>): bool acquires CountryRestrictionsRegistry {
        let registry = borrow_global<CountryRestrictionsRegistry>(@0x0); // This will need to be updated with actual address
        is_bilateral_transfer_blocked_internal(registry, source_country, destination_country)
    }
    
    /// Check if country transfer is valid
    public fun is_country_transfer_valid(source_country: vector<u8>, destination_country: vector<u8>, amount: u64): bool acquires CountryRestrictionsRegistry {
        let registry = borrow_global<CountryRestrictionsRegistry>(@0x0); // This will need to be updated with actual address
        
        // Check if global restrictions are enabled
        if (!registry.global_restrictions_enabled) {
            return true
        };
        
        // Copy values to avoid borrow checker issues
        let source_country_copy = source_country;
        let destination_country_copy = destination_country;
        
        // Check if source country is blocked
        if (is_country_blocked_internal(registry, source_country_copy)) {
            return false
        };
        
        // Check if destination country is blocked
        if (is_country_blocked_internal(registry, destination_country_copy)) {
            return false
        };
        
        // Check bilateral restrictions
        if (is_bilateral_transfer_blocked_internal(registry, source_country_copy, destination_country_copy)) {
            return false
        };
        
        // Check country-specific transfer limits
        if (table::contains(&registry.country_restrictions, destination_country)) {
            let restriction = table::borrow(&registry.country_restrictions, destination_country);
            if (amount > restriction.max_transfer_amount) {
                return false
            };
        };
        
        true
    }
    
    /// Get maximum transfer amount for country
    public fun get_max_transfer_amount_for_country(country_code: vector<u8>): u64 acquires CountryRestrictionsRegistry {
        let registry = borrow_global<CountryRestrictionsRegistry>(@0x0); // This will need to be updated with actual address
        
        if (!table::contains(&registry.country_restrictions, country_code)) {
            return registry.default_transfer_limit
        };
        
        let restriction = table::borrow(&registry.country_restrictions, country_code);
        restriction.max_transfer_amount
    }
    
    /// Enable global country restrictions
    public fun enable_global_restrictions(
        account: &signer
    ) acquires CountryRestrictionsRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<CountryRestrictionsRegistry>(account_addr);
        registry.global_restrictions_enabled = true;
    }
    
    /// Disable global country restrictions
    public fun disable_global_restrictions(
        account: &signer
    ) acquires CountryRestrictionsRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<CountryRestrictionsRegistry>(account_addr);
        registry.global_restrictions_enabled = false;
    }
    
    /// Check if global restrictions are enabled
    public fun are_global_restrictions_enabled(): bool acquires CountryRestrictionsRegistry {
        let registry = borrow_global<CountryRestrictionsRegistry>(@0x0); // This will need to be updated with actual address
        registry.global_restrictions_enabled
    }

    // ========== HELPER FUNCTIONS ==========
    
    /// Create bilateral restriction key
    fun create_bilateral_key(source_country: vector<u8>, destination_country: vector<u8>): String {
        // Create a unique key by concatenating country codes
        let key = source_country;
        vector::append(&mut key, destination_country);
        string::utf8(key)
    }
}
