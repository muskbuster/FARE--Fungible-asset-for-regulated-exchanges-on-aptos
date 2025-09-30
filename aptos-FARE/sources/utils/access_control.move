/// Access Control module for T-REX compliant token system
/// Implements role-based access control with time delays and multi-sig support

module FARE::access_control {
    use std::signer;
    use std::vector;
    use std::table::{Self, Table};
    use std::string::{Self, String};
    use std::timestamp;
    use std::error;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;
    use FARE::constants;

    // ========== STRUCTS ==========
    
    /// Role information for a user
    struct RoleInfo has store, copy, drop {
        role_type: u8,
        granted_by: address,
        granted_at: u64,
        expires_at: u64,
        is_active: bool,
    }
    
    /// Role transfer request
    struct RoleTransferRequest has store, copy, drop {
        from: address,
        to: address,
        role_type: u8,
        requested_at: u64,
        expires_at: u64,
        is_approved: bool,
        approved_by: vector<address>,
        required_approvals: u64,
    }
    
    /// Multi-sig configuration for a role
    struct MultiSigConfig has store, copy, drop {
        role_type: u8,
        required_signatures: u64,
        authorized_signers: vector<address>,
        is_active: bool,
    }
    
    /// Emergency pause configuration
    struct EmergencyPauseConfig has store, copy, drop {
        is_paused: bool,
        paused_by: address,
        paused_at: u64,
        pause_reason: String,
        unpause_authorized_by: vector<address>,
        required_unpause_approvals: u64,
    }
    
    /// Access control state
    struct AccessControl has key {
        /// Map of user address to their roles
        user_roles: Table<address, vector<RoleInfo>>,
        /// Map of role type to users who have that role
        role_users: Table<u8, vector<address>>,
        /// Pending role transfer requests
        role_transfer_requests: Table<u64, RoleTransferRequest>,
        /// Multi-sig configurations for roles
        multi_sig_configs: Table<u8, MultiSigConfig>,
        /// Emergency pause configuration
        emergency_pause: EmergencyPauseConfig,
        /// Next role transfer request ID
        next_role_transfer_id: u64,
        /// Role transfer delay (in seconds)
        role_transfer_delay: u64,
        /// Events
        role_granted_events: EventHandle<RoleGrantedEvent>,
        role_revoked_events: EventHandle<RoleRevokedEvent>,
        role_transfer_requested_events: EventHandle<RoleTransferRequestedEvent>,
        role_transfer_approved_events: EventHandle<RoleTransferApprovedEvent>,
        role_transfer_completed_events: EventHandle<RoleTransferCompletedEvent>,
        emergency_pause_events: EventHandle<EmergencyPauseEvent>,
        emergency_unpause_events: EventHandle<EmergencyUnpauseEvent>,
    }
    
    /// Role granted event
    struct RoleGrantedEvent has store, drop {
        user: address,
        role_type: u8,
        granted_by: address,
        granted_at: u64,
    }
    
    /// Role revoked event
    struct RoleRevokedEvent has store, drop {
        user: address,
        role_type: u8,
        revoked_by: address,
        revoked_at: u64,
    }
    
    /// Role transfer requested event
    struct RoleTransferRequestedEvent has store, drop {
        request_id: u64,
        from: address,
        to: address,
        role_type: u8,
        requested_at: u64,
        expires_at: u64,
    }
    
    /// Role transfer approved event
    struct RoleTransferApprovedEvent has store, drop {
        request_id: u64,
        approved_by: address,
        approved_at: u64,
        remaining_approvals: u64,
    }
    
    /// Role transfer completed event
    struct RoleTransferCompletedEvent has store, drop {
        request_id: u64,
        from: address,
        to: address,
        role_type: u8,
        completed_at: u64,
    }
    
    /// Emergency pause event
    struct EmergencyPauseEvent has store, drop {
        paused_by: address,
        paused_at: u64,
        pause_reason: String,
    }
    
    /// Emergency unpause event
    struct EmergencyUnpauseEvent has store, drop {
        unpaused_by: address,
        unpaused_at: u64,
    }

    // ========== INITIALIZATION ==========
    
    /// Initialize access control system
    public fun initialize(account: &signer) acquires AccessControl {
        let account_addr = signer::address_of(account);
        
        // Ensure account is not already initialized
        assert!(!exists<AccessControl>(account_addr), constants::get_access_control_not_authorized_error());
        
        let access_control = AccessControl {
            user_roles: table::new(),
            role_users: table::new(),
            role_transfer_requests: table::new(),
            multi_sig_configs: table::new(),
            emergency_pause: EmergencyPauseConfig {
                is_paused: false,
                paused_by: @0x0,
                paused_at: 0,
                pause_reason: string::utf8(b""),
                unpause_authorized_by: vector::empty(),
                required_unpause_approvals: 0,
            },
            next_role_transfer_id: 1,
            role_transfer_delay: constants::get_default_role_transfer_delay(),
            role_granted_events: account::new_event_handle<RoleGrantedEvent>(account),
            role_revoked_events: account::new_event_handle<RoleRevokedEvent>(account),
            role_transfer_requested_events: account::new_event_handle<RoleTransferRequestedEvent>(account),
            role_transfer_approved_events: account::new_event_handle<RoleTransferApprovedEvent>(account),
            role_transfer_completed_events: account::new_event_handle<RoleTransferCompletedEvent>(account),
            emergency_pause_events: account::new_event_handle<EmergencyPauseEvent>(account),
            emergency_unpause_events: account::new_event_handle<EmergencyUnpauseEvent>(account),
        };
        
        move_to(account, access_control);
        
        // Grant initial roles to the account
        grant_role(account, account_addr, constants::get_role_token_owner());
        grant_role(account, account_addr, constants::get_role_compliance_officer());
        grant_role(account, account_addr, constants::get_role_token_agent());
        grant_role(account, account_addr, constants::get_role_emergency_pause());
    }

    // ========== ROLE MANAGEMENT ==========
    
    /// Grant a role to a user
    public fun grant_role(
        account: &signer,
        user: address,
        role_type: u8
    ) acquires AccessControl {
        let account_addr = signer::address_of(account);
        let access_control = borrow_global_mut<AccessControl>(account_addr);
        
        // Check if system is paused
        assert!(!access_control.emergency_pause.is_paused, constants::get_token_paused_error());
        
        // Validate role type
        assert!(constants::is_valid_role_type(role_type), constants::get_invalid_parameter_error());
        
        // Check if user already has this role
        assert!(!has_role_internal(access_control, user, role_type), constants::get_access_control_not_authorized_error());
        
        let current_time = timestamp::now_seconds();
        let role_info = RoleInfo {
            role_type,
            granted_by: account_addr,
            granted_at: current_time,
            expires_at: 0, // Never expires by default
            is_active: true,
        };
        
        // Add role to user's roles
        if (!table::contains(&access_control.user_roles, user)) {
            table::add(&mut access_control.user_roles, user, vector::empty());
        };
        let user_roles = table::borrow_mut(&mut access_control.user_roles, user);
        vector::push_back(user_roles, role_info);
        
        // Add user to role's users
        if (!table::contains(&access_control.role_users, role_type)) {
            table::add(&mut access_control.role_users, role_type, vector::empty());
        };
        let role_users = table::borrow_mut(&mut access_control.role_users, role_type);
        vector::push_back(role_users, user);
        
        // Emit event
        event::emit_event(&mut access_control.role_granted_events, RoleGrantedEvent {
            user,
            role_type,
            granted_by: account_addr,
            granted_at: current_time,
        });
    }
    
    /// Revoke a role from a user
    public fun revoke_role(
        account: &signer,
        user: address,
        role_type: u8
    ) acquires AccessControl {
        let account_addr = signer::address_of(account);
        let access_control = borrow_global_mut<AccessControl>(account_addr);
        
        // Check if system is paused
        assert!(!access_control.emergency_pause.is_paused, constants::get_token_paused_error());
        
        // Validate role type
        assert!(constants::is_valid_role_type(role_type), constants::get_invalid_parameter_error());
        
        // Check if user has this role
        assert!(has_role_internal(access_control, user, role_type), constants::get_access_control_not_authorized_error());
        
        let current_time = timestamp::now_seconds();
        
        // Remove role from user's roles
        let user_roles = table::borrow_mut(&mut access_control.user_roles, user);
        let (found, index) = find_role_index(user_roles, role_type);
        assert!(found, constants::get_access_control_not_authorized_error());
        vector::remove(user_roles, index);
        
        // Remove user from role's users
        let role_users = table::borrow_mut(&mut access_control.role_users, role_type);
        let (found, index) = find_user_index(role_users, user);
        assert!(found, constants::get_access_control_not_authorized_error());
        vector::remove(role_users, index);
        
        // Emit event
        event::emit_event(&mut access_control.role_revoked_events, RoleRevokedEvent {
            user,
            role_type,
            revoked_by: account_addr,
            revoked_at: current_time,
        });
    }
    
    /// Request role transfer
    public fun request_role_transfer(
        account: &signer,
        to: address,
        role_type: u8
    ) acquires AccessControl {
        let from = signer::address_of(account);
        let access_control = borrow_global_mut<AccessControl>(from);
        
        // Check if system is paused
        assert!(!access_control.emergency_pause.is_paused, constants::get_token_paused_error());
        
        // Validate role type
        assert!(constants::is_valid_role_type(role_type), constants::get_invalid_parameter_error());
        
        // Check if user has this role
        assert!(has_role_internal(access_control, from, role_type), constants::get_access_control_not_authorized_error());
        
        // Check if target user already has this role
        assert!(!has_role_internal(access_control, to, role_type), constants::get_access_control_not_authorized_error());
        
        let current_time = timestamp::now_seconds();
        let request_id = access_control.next_role_transfer_id;
        access_control.next_role_transfer_id = access_control.next_role_transfer_id + 1;
        
        let request = RoleTransferRequest {
            from,
            to,
            role_type,
            requested_at: current_time,
            expires_at: current_time + access_control.role_transfer_delay,
            is_approved: false,
            approved_by: vector::empty(),
            required_approvals: 1, // Default to 1 approval
        };
        
        table::add(&mut access_control.role_transfer_requests, request_id, request);
        
        // Emit event
        event::emit_event(&mut access_control.role_transfer_requested_events, RoleTransferRequestedEvent {
            request_id,
            from,
            to,
            role_type,
            requested_at: current_time,
            expires_at: current_time + access_control.role_transfer_delay,
        });
    }
    
    /// Approve role transfer
    public fun approve_role_transfer(
        account: &signer,
        request_id: u64
    ) acquires AccessControl {
        let approver = signer::address_of(account);
        let access_control = borrow_global_mut<AccessControl>(approver);
        
        // Check if system is paused
        assert!(!access_control.emergency_pause.is_paused, constants::get_token_paused_error());
        
        // Check if request exists
        assert!(table::contains(&access_control.role_transfer_requests, request_id), constants::get_access_control_not_authorized_error());
        
        let request = table::borrow_mut(&mut access_control.role_transfer_requests, request_id);
        let current_time = timestamp::now_seconds();
        
        // Check if request is still valid
        assert!(current_time <= request.expires_at, constants::get_access_control_not_authorized_error());
        assert!(!request.is_approved, constants::get_access_control_not_authorized_error());
        
        // Check if approver has already approved
        let (found, _) = find_user_index(&request.approved_by, approver);
        assert!(!found, constants::get_access_control_not_authorized_error());
        
        // Add approver to approved list
        vector::push_back(&mut request.approved_by, approver);
        
        // Copy values before potentially calling complete_role_transfer_internal
        let required_approvals = request.required_approvals;
        let approved_by_len = vector::length(&request.approved_by);
        let remaining_approvals = required_approvals - approved_by_len;
        
        // Check if enough approvals
        if (approved_by_len >= required_approvals) {
            request.is_approved = true;
            
            // Complete the role transfer
            complete_role_transfer_internal(access_control, request_id);
        };
        
        // Emit event
        event::emit_event(&mut access_control.role_transfer_approved_events, RoleTransferApprovedEvent {
            request_id,
            approved_by: approver,
            approved_at: current_time,
            remaining_approvals,
        });
    }
    
    /// Complete role transfer (internal function)
    fun complete_role_transfer_internal(
        access_control: &mut AccessControl,
        request_id: u64
    ) {
        let request = table::borrow(&access_control.role_transfer_requests, request_id);
        
        // Copy values to avoid borrow checker issues
        let from = request.from;
        let to = request.to;
        let role_type = request.role_type;
        
        // Transfer the role
        revoke_role_internal(access_control, from, role_type);
        grant_role_internal(access_control, to, role_type, from);
        
        // Remove the request
        table::remove(&mut access_control.role_transfer_requests, request_id);
        
        // Emit event
        event::emit_event(&mut access_control.role_transfer_completed_events, RoleTransferCompletedEvent {
            request_id,
            from,
            to,
            role_type,
            completed_at: timestamp::now_seconds(),
        });
    }
    
    /// Grant role (internal function)
    fun grant_role_internal(
        access_control: &mut AccessControl,
        user: address,
        role_type: u8,
        granted_by: address
    ) {
        let current_time = timestamp::now_seconds();
        let role_info = RoleInfo {
            role_type,
            granted_by,
            granted_at: current_time,
            expires_at: 0, // Never expires by default
            is_active: true,
        };
        
        // Add role to user's roles
        if (!table::contains(&access_control.user_roles, user)) {
            table::add(&mut access_control.user_roles, user, vector::empty());
        };
        let user_roles = table::borrow_mut(&mut access_control.user_roles, user);
        vector::push_back(user_roles, role_info);
        
        // Add user to role's users
        if (!table::contains(&access_control.role_users, role_type)) {
            table::add(&mut access_control.role_users, role_type, vector::empty());
        };
        let role_users = table::borrow_mut(&mut access_control.role_users, role_type);
        vector::push_back(role_users, user);
    }
    
    /// Revoke role (internal function)
    fun revoke_role_internal(
        access_control: &mut AccessControl,
        user: address,
        role_type: u8
    ) {
        // Remove role from user's roles
        let user_roles = table::borrow_mut(&mut access_control.user_roles, user);
        let (found, index) = find_role_index(user_roles, role_type);
        assert!(found, constants::get_access_control_not_authorized_error());
        vector::remove(user_roles, index);
        
        // Remove user from role's users
        let role_users = table::borrow_mut(&mut access_control.role_users, role_type);
        let (found, index) = find_user_index(role_users, user);
        assert!(found, constants::get_access_control_not_authorized_error());
        vector::remove(role_users, index);
    }

    // ========== EMERGENCY PAUSE ==========
    
    /// Emergency pause the system
    public fun emergency_pause(
        account: &signer,
        reason: String
    ) acquires AccessControl {
        let pauser = signer::address_of(account);
        let access_control = borrow_global_mut<AccessControl>(pauser);
        
        // Check if system is already paused
        assert!(!access_control.emergency_pause.is_paused, constants::get_token_paused_error());
        
        // Check if user has emergency pause role
        assert!(has_role_internal(access_control, pauser, constants::get_role_emergency_pause()), constants::get_access_control_not_authorized_error());
        
        let current_time = timestamp::now_seconds();
        access_control.emergency_pause = EmergencyPauseConfig {
            is_paused: true,
            paused_by: pauser,
            paused_at: current_time,
            pause_reason: reason,
            unpause_authorized_by: vector::empty(),
            required_unpause_approvals: 1, // Default to 1 approval
        };
        
        // Emit event
        event::emit_event(&mut access_control.emergency_pause_events, EmergencyPauseEvent {
            paused_by: pauser,
            paused_at: current_time,
            pause_reason: reason,
        });
    }
    
    /// Emergency unpause the system
    public fun emergency_unpause(
        account: &signer
    ) acquires AccessControl {
        let unpauser = signer::address_of(account);
        let access_control = borrow_global_mut<AccessControl>(unpauser);
        
        // Check if system is paused
        assert!(access_control.emergency_pause.is_paused, constants::get_token_paused_error());
        
        // Check if user has emergency pause role
        assert!(has_role_internal(access_control, unpauser, constants::get_role_emergency_pause()), constants::get_access_control_not_authorized_error());
        
        let current_time = timestamp::now_seconds();
        access_control.emergency_pause = EmergencyPauseConfig {
            is_paused: false,
            paused_by: @0x0,
            paused_at: 0,
            pause_reason: string::utf8(b""),
            unpause_authorized_by: vector::empty(),
            required_unpause_approvals: 0,
        };
        
        // Emit event
        event::emit_event(&mut access_control.emergency_unpause_events, EmergencyUnpauseEvent {
            unpaused_by: unpauser,
            unpaused_at: current_time,
        });
    }

    // ========== VIEW FUNCTIONS ==========
    
    /// Check if user has a specific role
    public fun has_role(user: address, role_type: u8): bool acquires AccessControl {
        let access_control = borrow_global<AccessControl>(user);
        has_role_internal(access_control, user, role_type)
    }
    
    /// Check if user has a specific role (internal)
    fun has_role_internal(access_control: &AccessControl, user: address, role_type: u8): bool {
        if (!table::contains(&access_control.user_roles, user)) {
            return false
        };
        
        let user_roles = table::borrow(&access_control.user_roles, user);
        let (found, _) = find_role_index(user_roles, role_type);
        found
    }
    
    /// Get all roles for a user
    public fun get_user_roles(user: address): vector<u8> acquires AccessControl {
        let access_control = borrow_global<AccessControl>(user);
        let roles = vector::empty();
        
        if (table::contains(&access_control.user_roles, user)) {
            let user_roles = table::borrow(&access_control.user_roles, user);
            let len = vector::length(user_roles);
            let i = 0;
            while (i < len) {
                let role_info = vector::borrow(user_roles, i);
                if (role_info.is_active) {
                    vector::push_back(&mut roles, role_info.role_type);
                };
                i = i + 1;
            };
        };
        
        roles
    }
    
    /// Get all users with a specific role
    public fun get_role_users(role_type: u8): vector<address> acquires AccessControl {
        let access_control = borrow_global<AccessControl>(@0x0);
        let users = vector::empty();
        
        if (table::contains(&access_control.role_users, role_type)) {
            let role_users = table::borrow(&access_control.role_users, role_type);
            let len = vector::length(role_users);
            let i = 0;
            while (i < len) {
                let user = *vector::borrow(role_users, i);
                if (has_role_internal(access_control, user, role_type)) {
                    vector::push_back(&mut users, user);
                };
                i = i + 1;
            };
        };
        
        users
    }
    
    /// Check if system is paused
    public fun is_system_paused(): bool acquires AccessControl {
        let access_control = borrow_global<AccessControl>(@0x0); // This will need to be updated with actual address
        access_control.emergency_pause.is_paused
    }
    
    /// Get emergency pause information
    public fun get_emergency_pause_info(): (bool, address, u64, String) acquires AccessControl {
        let access_control = borrow_global<AccessControl>(@0x0); // This will need to be updated with actual address
        (
            access_control.emergency_pause.is_paused,
            access_control.emergency_pause.paused_by,
            access_control.emergency_pause.paused_at,
            access_control.emergency_pause.pause_reason,
        )
    }
    
    /// Get role transfer request information
    public fun get_role_transfer_request(request_id: u64): (address, address, u8, u64, u64, bool, vector<address>, u64) acquires AccessControl {
        let access_control = borrow_global<AccessControl>(@0x0); // This will need to be updated with actual address
        assert!(table::contains(&access_control.role_transfer_requests, request_id), constants::get_access_control_not_authorized_error());
        
        let request = table::borrow(&access_control.role_transfer_requests, request_id);
        (
            request.from,
            request.to,
            request.role_type,
            request.requested_at,
            request.expires_at,
            request.is_approved,
            request.approved_by,
            request.required_approvals,
        )
    }

    // ========== HELPER FUNCTIONS ==========
    
    /// Find role index in user roles vector
    fun find_role_index(user_roles: &vector<RoleInfo>, role_type: u8): (bool, u64) {
        let len = vector::length(user_roles);
        let i = 0;
        while (i < len) {
            let role_info = vector::borrow(user_roles, i);
            if (role_info.role_type == role_type && role_info.is_active) {
                return (true, i)
            };
            i = i + 1;
        };
        (false, 0)
    }
    
    /// Find user index in role users vector
    fun find_user_index(role_users: &vector<address>, user: address): (bool, u64) {
        let len = vector::length(role_users);
        let i = 0;
        while (i < len) {
            let role_user = *vector::borrow(role_users, i);
            if (role_user == user) {
                return (true, i)
            };
            i = i + 1;
        };
        (false, 0)
    }
    
    /// Set role transfer delay
    public fun set_role_transfer_delay(
        account: &signer,
        delay: u64
    ) acquires AccessControl {
        let account_addr = signer::address_of(account);
        let access_control = borrow_global_mut<AccessControl>(account_addr);
        
        // Check if user has token owner role
        assert!(has_role_internal(access_control, account_addr, constants::get_role_token_owner()), constants::get_access_control_not_authorized_error());
        
        access_control.role_transfer_delay = delay;
    }
    
    /// Get role transfer delay
    public fun get_role_transfer_delay(): u64 acquires AccessControl {
        let access_control = borrow_global<AccessControl>(@0x0); // This will need to be updated with actual address
        access_control.role_transfer_delay
    }
}
