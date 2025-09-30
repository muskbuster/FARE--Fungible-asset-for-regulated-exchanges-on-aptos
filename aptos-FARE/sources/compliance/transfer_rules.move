/// Transfer Rules module for T-REX compliant token system
/// Implements transfer restrictions and validation rules

module FARE::transfer_rules {
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
    
    /// Transfer restrictions for a user
    struct TransferRestrictions has store, copy, drop {
        /// Maximum transfer amount per transaction
        max_transfer_amount: u64,
        /// Daily transfer volume limit
        daily_transfer_limit: u64,
        /// Monthly transfer volume limit
        monthly_transfer_limit: u64,
        /// Maximum number of transfers per day
        daily_transfer_count: u64,
        /// Maximum number of transfers per month
        monthly_transfer_count: u64,
        /// Transfer lock duration (seconds)
        transfer_lock_duration: u64,
        /// Last transfer timestamp
        last_transfer_timestamp: u64,
        /// Daily transfer volume used
        daily_volume_used: u64,
        /// Monthly transfer volume used
        monthly_volume_used: u64,
        /// Daily transfer count used
        daily_count_used: u64,
        /// Monthly transfer count used
        monthly_count_used: u64,
        /// Last reset date for daily limits
        last_daily_reset: u64,
        /// Last reset date for monthly limits
        last_monthly_reset: u64,
    }
    
    /// Trading hours configuration
    struct TradingHours has store, copy, drop {
        /// Start time (seconds since midnight UTC)
        start_time: u64,
        /// End time (seconds since midnight UTC)
        end_time: u64,
        /// Days of week when trading is allowed (bitmask: 1=Sunday, 2=Monday, etc.)
        allowed_days: u8,
        /// Whether trading hours are enforced
        is_enforced: bool,
    }
    
    /// Transfer validation result
    struct TransferValidationResult has store, copy, drop {
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
    
    /// Transfer rules registry
    struct TransferRulesRegistry has key {
        /// Map of user to transfer restrictions
        user_restrictions: Table<address, TransferRestrictions>,
        /// Trading hours configuration
        trading_hours: TradingHours,
        /// Global transfer restrictions
        global_restrictions: TransferRestrictions,
        /// Events
        transfer_restriction_updated_events: EventHandle<TransferRestrictionUpdatedEvent>,
        trading_hours_updated_events: EventHandle<TradingHoursUpdatedEvent>,
        transfer_validated_events: EventHandle<TransferValidatedEvent>,
        transfer_blocked_events: EventHandle<TransferBlockedEvent>,
    }
    
    /// Transfer restriction updated event
    struct TransferRestrictionUpdatedEvent has store, drop {
        user: address,
        updated_by: address,
        updated_at: u64,
    }
    
    /// Trading hours updated event
    struct TradingHoursUpdatedEvent has store, drop {
        start_time: u64,
        end_time: u64,
        allowed_days: u8,
        updated_by: address,
        updated_at: u64,
    }
    
    /// Transfer validated event
    struct TransferValidatedEvent has store, drop {
        user: address,
        amount: u64,
        is_valid: bool,
        validated_at: u64,
    }
    
    /// Transfer blocked event
    struct TransferBlockedEvent has store, drop {
        user: address,
        amount: u64,
        reason: String,
        blocked_at: u64,
    }

    // ========== INITIALIZATION ==========
    
    /// Initialize transfer rules registry
    public fun initialize(account: &signer) {
        let account_addr = signer::address_of(account);
        
        // Ensure account is not already initialized
        assert!(!exists<TransferRulesRegistry>(account_addr), constants::get_access_control_not_authorized_error());
        
        let registry = TransferRulesRegistry {
            user_restrictions: table::new(),
            trading_hours: TradingHours {
                start_time: constants::get_default_trading_hours_start(),
                end_time: constants::get_default_trading_hours_end(),
                allowed_days: 127, // All days (binary: 1111111)
                is_enforced: false,
            },
            global_restrictions: TransferRestrictions {
                max_transfer_amount: constants::get_max_transfer_amount(),
                daily_transfer_limit: constants::get_max_daily_transfer_volume(),
                monthly_transfer_limit: constants::get_max_daily_transfer_volume() * 30,
                daily_transfer_count: 100,
                monthly_transfer_count: 1000,
                transfer_lock_duration: 0,
                last_transfer_timestamp: 0,
                daily_volume_used: 0,
                monthly_volume_used: 0,
                daily_count_used: 0,
                monthly_count_used: 0,
                last_daily_reset: 0,
                last_monthly_reset: 0,
            },
            transfer_restriction_updated_events: account::new_event_handle<TransferRestrictionUpdatedEvent>(account),
            trading_hours_updated_events: account::new_event_handle<TradingHoursUpdatedEvent>(account),
            transfer_validated_events: account::new_event_handle<TransferValidatedEvent>(account),
            transfer_blocked_events: account::new_event_handle<TransferBlockedEvent>(account),
        };
        
        move_to(account, registry);
    }

    // ========== TRANSFER RESTRICTIONS MANAGEMENT ==========
    
    /// Set transfer restrictions for a user
    public fun set_user_transfer_restrictions(
        account: &signer,
        user: address,
        max_transfer_amount: u64,
        daily_transfer_limit: u64,
        monthly_transfer_limit: u64,
        daily_transfer_count: u64,
        monthly_transfer_count: u64,
        transfer_lock_duration: u64
    ) acquires TransferRulesRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TransferRulesRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Validate parameters
        assert!(constants::is_valid_amount(max_transfer_amount), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_amount(daily_transfer_limit), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_amount(monthly_transfer_limit), constants::get_invalid_parameter_error());
        assert!(daily_transfer_count > 0, constants::get_invalid_parameter_error());
        assert!(monthly_transfer_count > 0, constants::get_invalid_parameter_error());
        assert!(constants::is_valid_duration(transfer_lock_duration), constants::get_invalid_parameter_error());
        
        let restrictions = TransferRestrictions {
            max_transfer_amount,
            daily_transfer_limit,
            monthly_transfer_limit,
            daily_transfer_count,
            monthly_transfer_count,
            transfer_lock_duration,
            last_transfer_timestamp: 0,
            daily_volume_used: 0,
            monthly_volume_used: 0,
            daily_count_used: 0,
            monthly_count_used: 0,
            last_daily_reset: current_time,
            last_monthly_reset: current_time,
        };
        
        table::add(&mut registry.user_restrictions, user, restrictions);
        
        // Emit event
        event::emit_event(&mut registry.transfer_restriction_updated_events, TransferRestrictionUpdatedEvent {
            user,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }
    
    /// Update user transfer restrictions
    public fun update_user_transfer_restrictions(
        account: &signer,
        user: address,
        max_transfer_amount: u64,
        daily_transfer_limit: u64,
        monthly_transfer_limit: u64,
        daily_transfer_count: u64,
        monthly_transfer_count: u64,
        transfer_lock_duration: u64
    ) acquires TransferRulesRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TransferRulesRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if user has restrictions
        assert!(table::contains(&registry.user_restrictions, user), constants::get_compliance_module_not_found_error());
        
        // Validate parameters
        assert!(constants::is_valid_amount(max_transfer_amount), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_amount(daily_transfer_limit), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_amount(monthly_transfer_limit), constants::get_invalid_parameter_error());
        assert!(daily_transfer_count > 0, constants::get_invalid_parameter_error());
        assert!(monthly_transfer_count > 0, constants::get_invalid_parameter_error());
        assert!(constants::is_valid_duration(transfer_lock_duration), constants::get_invalid_parameter_error());
        
        let restrictions = table::borrow_mut(&mut registry.user_restrictions, user);
        restrictions.max_transfer_amount = max_transfer_amount;
        restrictions.daily_transfer_limit = daily_transfer_limit;
        restrictions.monthly_transfer_limit = monthly_transfer_limit;
        restrictions.daily_transfer_count = daily_transfer_count;
        restrictions.monthly_transfer_count = monthly_transfer_count;
        restrictions.transfer_lock_duration = transfer_lock_duration;
        
        // Emit event
        event::emit_event(&mut registry.transfer_restriction_updated_events, TransferRestrictionUpdatedEvent {
            user,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }
    
    /// Remove user transfer restrictions
    public fun remove_user_transfer_restrictions(
        account: &signer,
        user: address
    ) acquires TransferRulesRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TransferRulesRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if user has restrictions
        assert!(table::contains(&registry.user_restrictions, user), constants::get_compliance_module_not_found_error());
        
        table::remove(&mut registry.user_restrictions, user);
        
        // Emit event
        event::emit_event(&mut registry.transfer_restriction_updated_events, TransferRestrictionUpdatedEvent {
            user,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }

    // ========== TRADING HOURS MANAGEMENT ==========
    
    /// Set trading hours
    public fun set_trading_hours(
        account: &signer,
        start_time: u64,
        end_time: u64,
        allowed_days: u8,
        is_enforced: bool
    ) acquires TransferRulesRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TransferRulesRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Validate parameters
        assert!(start_time < 86400, constants::get_invalid_parameter_error()); // 24 hours in seconds
        assert!(end_time < 86400, constants::get_invalid_parameter_error());
        assert!(start_time < end_time, constants::get_invalid_parameter_error());
        assert!(allowed_days > 0, constants::get_invalid_parameter_error());
        
        registry.trading_hours.start_time = start_time;
        registry.trading_hours.end_time = end_time;
        registry.trading_hours.allowed_days = allowed_days;
        registry.trading_hours.is_enforced = is_enforced;
        
        // Emit event
        event::emit_event(&mut registry.trading_hours_updated_events, TradingHoursUpdatedEvent {
            start_time,
            end_time,
            allowed_days,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }
    
    /// Enable trading hours enforcement
    public fun enable_trading_hours_enforcement(
        account: &signer
    ) acquires TransferRulesRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TransferRulesRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        registry.trading_hours.is_enforced = true;
        
        // Emit event
        event::emit_event(&mut registry.trading_hours_updated_events, TradingHoursUpdatedEvent {
            start_time: registry.trading_hours.start_time,
            end_time: registry.trading_hours.end_time,
            allowed_days: registry.trading_hours.allowed_days,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }
    
    /// Disable trading hours enforcement
    public fun disable_trading_hours_enforcement(
        account: &signer
    ) acquires TransferRulesRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TransferRulesRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        registry.trading_hours.is_enforced = false;
        
        // Emit event
        event::emit_event(&mut registry.trading_hours_updated_events, TradingHoursUpdatedEvent {
            start_time: registry.trading_hours.start_time,
            end_time: registry.trading_hours.end_time,
            allowed_days: registry.trading_hours.allowed_days,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }

    // ========== TRANSFER VALIDATION ==========
    
    /// Validate a transfer
    public fun validate_transfer(
        account: &signer,
        user: address,
        amount: u64
    ): TransferValidationResult acquires TransferRulesRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TransferRulesRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Validate amount
        if (!constants::is_valid_amount(amount)) {
            let result = TransferValidationResult {
                is_valid: false,
                error_code: constants::get_invalid_amount_error(),
                error_message: string::utf8(b"Invalid transfer amount"),
                validation_data: vector::empty(),
                validated_at: current_time,
            };
            
            // Emit event
            event::emit_event(&mut registry.transfer_blocked_events, TransferBlockedEvent {
                user,
                amount,
                reason: string::utf8(b"Invalid transfer amount"),
                blocked_at: current_time,
            });
            
            return result
        };
        
        // Copy current_time to avoid borrow checker issues
        let current_time_copy = current_time;
        
        // Check trading hours
        if (registry.trading_hours.is_enforced && !is_within_trading_hours_internal(registry, current_time_copy)) {
            let result = TransferValidationResult {
                is_valid: false,
                error_code: constants::get_compliance_trading_hours_error(),
                error_message: string::utf8(b"Transfer outside trading hours"),
                validation_data: vector::empty(),
                validated_at: current_time,
            };
            
            // Emit event
            event::emit_event(&mut registry.transfer_blocked_events, TransferBlockedEvent {
                user,
                amount,
                reason: string::utf8(b"Transfer outside trading hours"),
                blocked_at: current_time,
            });
            
            return result
        };
        
        // Get user restrictions (use global if user-specific not found)
        let restrictions = if (table::contains(&registry.user_restrictions, user)) {
            *table::borrow(&registry.user_restrictions, user)
        } else {
            registry.global_restrictions
        };
        
        // Check transfer lock
        if (restrictions.transfer_lock_duration > 0 && 
            restrictions.last_transfer_timestamp > 0 &&
            current_time - restrictions.last_transfer_timestamp < restrictions.transfer_lock_duration) {
            let result = TransferValidationResult {
                is_valid: false,
                error_code: constants::get_compliance_transfer_lock_error(),
                error_message: string::utf8(b"Transfer locked due to recent transfer"),
                validation_data: vector::empty(),
                validated_at: current_time,
            };
            
            // Emit event
            event::emit_event(&mut registry.transfer_blocked_events, TransferBlockedEvent {
                user,
                amount,
                reason: string::utf8(b"Transfer locked due to recent transfer"),
                blocked_at: current_time,
            });
            
            return result
        };
        
        // Check maximum transfer amount
        if (amount > restrictions.max_transfer_amount) {
            let result = TransferValidationResult {
                is_valid: false,
                error_code: constants::get_compliance_transfer_restricted_error(),
                error_message: string::utf8(b"Transfer amount exceeds maximum allowed"),
                validation_data: vector::empty(),
                validated_at: current_time,
            };
            
            // Emit event
            event::emit_event(&mut registry.transfer_blocked_events, TransferBlockedEvent {
                user,
                amount,
                reason: string::utf8(b"Transfer amount exceeds maximum allowed"),
                blocked_at: current_time,
            });
            
            return result
        };
        
        // Check daily limits
        if (restrictions.daily_volume_used + amount > restrictions.daily_transfer_limit) {
            let result = TransferValidationResult {
                is_valid: false,
                error_code: constants::get_compliance_daily_limit_exceeded_error(),
                error_message: string::utf8(b"Daily transfer limit exceeded"),
                validation_data: vector::empty(),
                validated_at: current_time,
            };
            
            // Emit event
            event::emit_event(&mut registry.transfer_blocked_events, TransferBlockedEvent {
                user,
                amount,
                reason: string::utf8(b"Daily transfer limit exceeded"),
                blocked_at: current_time,
            });
            
            return result
        };
        
        // Check monthly limits
        if (restrictions.monthly_volume_used + amount > restrictions.monthly_transfer_limit) {
            let result = TransferValidationResult {
                is_valid: false,
                error_code: constants::get_compliance_daily_limit_exceeded_error(),
                error_message: string::utf8(b"Monthly transfer limit exceeded"),
                validation_data: vector::empty(),
                validated_at: current_time,
            };
            
            // Emit event
            event::emit_event(&mut registry.transfer_blocked_events, TransferBlockedEvent {
                user,
                amount,
                reason: string::utf8(b"Monthly transfer limit exceeded"),
                blocked_at: current_time,
            });
            
            return result
        };
        
        // Check daily transfer count
        if (restrictions.daily_count_used >= restrictions.daily_transfer_count) {
            let result = TransferValidationResult {
                is_valid: false,
                error_code: constants::get_compliance_daily_limit_exceeded_error(),
                error_message: string::utf8(b"Daily transfer count limit exceeded"),
                validation_data: vector::empty(),
                validated_at: current_time,
            };
            
            // Emit event
            event::emit_event(&mut registry.transfer_blocked_events, TransferBlockedEvent {
                user,
                amount,
                reason: string::utf8(b"Daily transfer count limit exceeded"),
                blocked_at: current_time,
            });
            
            return result
        };
        
        // Check monthly transfer count
        if (restrictions.monthly_count_used >= restrictions.monthly_transfer_count) {
            let result = TransferValidationResult {
                is_valid: false,
                error_code: constants::get_compliance_daily_limit_exceeded_error(),
                error_message: string::utf8(b"Monthly transfer count limit exceeded"),
                validation_data: vector::empty(),
                validated_at: current_time,
            };
            
            // Emit event
            event::emit_event(&mut registry.transfer_blocked_events, TransferBlockedEvent {
                user,
                amount,
                reason: string::utf8(b"Monthly transfer count limit exceeded"),
                blocked_at: current_time,
            });
            
            return result
        };
        
        // Transfer is valid
        let result = TransferValidationResult {
            is_valid: true,
            error_code: 0,
            error_message: string::utf8(b"Transfer is valid"),
            validation_data: vector::empty(),
            validated_at: current_time,
        };
        
        // Emit event
        event::emit_event(&mut registry.transfer_validated_events, TransferValidatedEvent {
            user,
            amount,
            is_valid: true,
            validated_at: current_time,
        });
        
        result
    }
    
    /// Record a successful transfer
    public fun record_transfer(
        account: &signer,
        user: address,
        amount: u64
    ) acquires TransferRulesRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TransferRulesRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Get user restrictions (use global if user-specific not found)
        let restrictions = if (table::contains(&registry.user_restrictions, user)) {
            table::borrow_mut(&mut registry.user_restrictions, user)
        } else {
            &mut registry.global_restrictions
        };
        
        // Reset daily limits if needed
        if (current_time - restrictions.last_daily_reset >= 86400) { // 24 hours
            restrictions.daily_volume_used = 0;
            restrictions.daily_count_used = 0;
            restrictions.last_daily_reset = current_time;
        };
        
        // Reset monthly limits if needed
        if (current_time - restrictions.last_monthly_reset >= 2592000) { // 30 days
            restrictions.monthly_volume_used = 0;
            restrictions.monthly_count_used = 0;
            restrictions.last_monthly_reset = current_time;
        };
        
        // Update transfer statistics
        restrictions.last_transfer_timestamp = current_time;
        restrictions.daily_volume_used = restrictions.daily_volume_used + amount;
        restrictions.monthly_volume_used = restrictions.monthly_volume_used + amount;
        restrictions.daily_count_used = restrictions.daily_count_used + 1;
        restrictions.monthly_count_used = restrictions.monthly_count_used + 1;
    }

    // ========== VIEW FUNCTIONS ==========
    
    /// Get user transfer restrictions
    public fun get_user_transfer_restrictions(user: address): (u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64, u64) acquires TransferRulesRegistry {
        let registry = borrow_global<TransferRulesRegistry>(user);
        
        if (!table::contains(&registry.user_restrictions, user)) {
            let global = registry.global_restrictions;
            return (
                global.max_transfer_amount,
                global.daily_transfer_limit,
                global.monthly_transfer_limit,
                global.daily_transfer_count,
                global.monthly_transfer_count,
                global.transfer_lock_duration,
                global.last_transfer_timestamp,
                global.daily_volume_used,
                global.monthly_volume_used,
                global.daily_count_used,
                global.monthly_count_used,
                global.last_daily_reset,
                global.last_monthly_reset,
            )
        };
        
        let restrictions = table::borrow(&registry.user_restrictions, user);
        (
            restrictions.max_transfer_amount,
            restrictions.daily_transfer_limit,
            restrictions.monthly_transfer_limit,
            restrictions.daily_transfer_count,
            restrictions.monthly_transfer_count,
            restrictions.transfer_lock_duration,
            restrictions.last_transfer_timestamp,
            restrictions.daily_volume_used,
            restrictions.monthly_volume_used,
            restrictions.daily_count_used,
            restrictions.monthly_count_used,
            restrictions.last_daily_reset,
            restrictions.last_monthly_reset,
        )
    }
    
    /// Get trading hours configuration
    public fun get_trading_hours(): (u64, u64, u8, bool) acquires TransferRulesRegistry {
        let registry = borrow_global<TransferRulesRegistry>(@0x0); // This will need to be updated with actual address
        (
            registry.trading_hours.start_time,
            registry.trading_hours.end_time,
            registry.trading_hours.allowed_days,
            registry.trading_hours.is_enforced,
        )
    }
    
    /// Check if current time is within trading hours (internal function without acquires)
    fun is_within_trading_hours_internal(registry: &TransferRulesRegistry, current_time: u64): bool {
        if (!registry.trading_hours.is_enforced) {
            return true
        };
        
        // Get current time of day (seconds since midnight UTC)
        let time_of_day = current_time % 86400;
        
        // Check if within trading hours
        if (time_of_day < registry.trading_hours.start_time || time_of_day > registry.trading_hours.end_time) {
            return false
        };
        
        // Check if current day is allowed
        let day_of_week = (current_time / 86400) % 7; // 0 = Sunday, 1 = Monday, etc.
        let day_bit = 1 << (day_of_week as u8);
        
        (registry.trading_hours.allowed_days & day_bit) > 0
    }
    
    /// Check if current time is within trading hours
    public fun is_within_trading_hours(current_time: u64): bool acquires TransferRulesRegistry {
        let registry = borrow_global<TransferRulesRegistry>(@0x0); // This will need to be updated with actual address
        is_within_trading_hours_internal(registry, current_time)
    }
    
    /// Check if user can transfer amount
    public fun can_user_transfer(user: address, amount: u64): bool acquires TransferRulesRegistry {
        let registry = borrow_global<TransferRulesRegistry>(user);
        let current_time = timestamp::now_seconds();
        
        // Copy current_time to avoid borrow checker issues
        let current_time_copy = current_time;
        
        // Check trading hours
        if (registry.trading_hours.is_enforced && !is_within_trading_hours_internal(registry, current_time_copy)) {
            return false
        };
        
        // Get user restrictions (use global if user-specific not found)
        let restrictions = if (table::contains(&registry.user_restrictions, user)) {
            *table::borrow(&registry.user_restrictions, user)
        } else {
            registry.global_restrictions
        };
        
        // Check transfer lock
        if (restrictions.transfer_lock_duration > 0 && 
            restrictions.last_transfer_timestamp > 0 &&
            current_time - restrictions.last_transfer_timestamp < restrictions.transfer_lock_duration) {
            return false
        };
        
        // Check maximum transfer amount
        if (amount > restrictions.max_transfer_amount) {
            return false
        };
        
        // Check daily limits
        if (restrictions.daily_volume_used + amount > restrictions.daily_transfer_limit) {
            return false
        };
        
        // Check monthly limits
        if (restrictions.monthly_volume_used + amount > restrictions.monthly_transfer_limit) {
            return false
        };
        
        // Check daily transfer count
        if (restrictions.daily_count_used >= restrictions.daily_transfer_count) {
            return false
        };
        
        // Check monthly transfer count
        if (restrictions.monthly_count_used >= restrictions.monthly_transfer_count) {
            return false
        };
        
        true
    }
    
    /// Get user's remaining daily transfer limit
    public fun get_remaining_daily_limit(user: address): u64 acquires TransferRulesRegistry {
        let registry = borrow_global<TransferRulesRegistry>(user);
        
        let restrictions = if (table::contains(&registry.user_restrictions, user)) {
            *table::borrow(&registry.user_restrictions, user)
        } else {
            registry.global_restrictions
        };
        
        if (restrictions.daily_volume_used >= restrictions.daily_transfer_limit) {
            return 0
        };
        
        restrictions.daily_transfer_limit - restrictions.daily_volume_used
    }
    
    /// Get user's remaining monthly transfer limit
    public fun get_remaining_monthly_limit(user: address): u64 acquires TransferRulesRegistry {
        let registry = borrow_global<TransferRulesRegistry>(user);
        
        let restrictions = if (table::contains(&registry.user_restrictions, user)) {
            *table::borrow(&registry.user_restrictions, user)
        } else {
            registry.global_restrictions
        };
        
        if (restrictions.monthly_volume_used >= restrictions.monthly_transfer_limit) {
            return 0
        };
        
        restrictions.monthly_transfer_limit - restrictions.monthly_volume_used
    }
    
    /// Get user's remaining daily transfer count
    public fun get_remaining_daily_count(user: address): u64 acquires TransferRulesRegistry {
        let registry = borrow_global<TransferRulesRegistry>(user);
        
        let restrictions = if (table::contains(&registry.user_restrictions, user)) {
            *table::borrow(&registry.user_restrictions, user)
        } else {
            registry.global_restrictions
        };
        
        if (restrictions.daily_count_used >= restrictions.daily_transfer_count) {
            return 0
        };
        
        restrictions.daily_transfer_count - restrictions.daily_count_used
    }
    
    /// Get user's remaining monthly transfer count
    public fun get_remaining_monthly_count(user: address): u64 acquires TransferRulesRegistry {
        let registry = borrow_global<TransferRulesRegistry>(user);
        
        let restrictions = if (table::contains(&registry.user_restrictions, user)) {
            *table::borrow(&registry.user_restrictions, user)
        } else {
            registry.global_restrictions
        };
        
        if (restrictions.monthly_count_used >= restrictions.monthly_transfer_count) {
            return 0
        };
        
        restrictions.monthly_transfer_count - restrictions.monthly_count_used
    }
}
