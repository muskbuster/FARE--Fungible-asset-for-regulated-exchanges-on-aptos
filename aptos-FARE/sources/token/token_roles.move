/// Token Roles module for T-REX compliant token system
/// Manages role-based access control for token operations

module FARE::token_roles {
    use std::vector;
    use std::string::{Self, String};
    use std::table::{Self, Table};
    use std::error;
    use std::signer;
    use std::timestamp;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;
    use FARE::constants;
    use FARE::access_control;

    // ========== STRUCTS ==========
    
    /// Token role information
    struct TokenRoleInfo has store, copy, drop {
        /// Role type
        role_type: u8,
        /// User address
        user: address,
        /// Granted by
        granted_by: address,
        /// Granted timestamp
        granted_at: u64,
        /// Expires timestamp (0 = never expires)
        expires_at: u64,
        /// Whether role is active
        is_active: bool,
        /// Role permissions
        permissions: vector<u8>,
    }
    
    /// Token role permissions
    struct TokenRolePermissions has store, copy, drop {
        /// Can mint tokens
        can_mint: bool,
        /// Can burn tokens
        can_burn: bool,
        /// Can pause token
        can_pause: bool,
        /// Can freeze accounts
        can_freeze_accounts: bool,
        /// Can force transfer
        can_force_transfer: bool,
        /// Can update compliance
        can_update_compliance: bool,
        /// Can update metadata
        can_update_metadata: bool,
        /// Can manage roles
        can_manage_roles: bool,
        /// Can emergency pause
        can_emergency_pause: bool,
        /// Can recover assets
        can_recover_assets: bool,
    }
    
    /// Account freeze information
    struct AccountFreezeInfo has store, copy, drop {
        /// Whether account is frozen
        is_frozen: bool,
        /// Freeze reason
        freeze_reason: String,
        /// Frozen by
        frozen_by: address,
        /// Frozen timestamp
        frozen_at: u64,
        /// Whether account is partially frozen
        is_partially_frozen: bool,
        /// Partial freeze permissions
        partial_freeze_permissions: vector<u8>,
    }
    
    /// Asset recovery information
    struct AssetRecoveryInfo has store, copy, drop {
        /// Recovery request ID
        recovery_id: u64,
        /// Account to recover from
        from_account: address,
        /// Account to recover to
        to_account: address,
        /// Recovery amount
        amount: u64,
        /// Recovery reason
        recovery_reason: String,
        /// Requested by
        requested_by: address,
        /// Requested timestamp
        requested_at: u64,
        /// Approved by
        approved_by: vector<address>,
        /// Required approvals
        required_approvals: u64,
        /// Recovery status
        status: u8,
        /// Executed timestamp
        executed_at: u64,
    }
    
    /// Token roles registry
    struct TokenRolesRegistry has key {
        /// Map of token address to role information
        token_roles: Table<address, Table<address, TokenRoleInfo>>,
        /// Map of token address to account freeze info
        account_freezes: Table<address, Table<address, AccountFreezeInfo>>,
        /// Map of token address to asset recovery info
        asset_recoveries: Table<address, Table<u64, AssetRecoveryInfo>>,
        /// Next recovery ID
        next_recovery_id: u64,
        /// Events
        role_granted_events: EventHandle<TokenRoleGrantedEvent>,
        role_revoked_events: EventHandle<TokenRoleRevokedEvent>,
        account_frozen_events: EventHandle<AccountFrozenEvent>,
        account_unfrozen_events: EventHandle<AccountUnfrozenEvent>,
        asset_recovery_requested_events: EventHandle<AssetRecoveryRequestedEvent>,
        asset_recovery_approved_events: EventHandle<AssetRecoveryApprovedEvent>,
        asset_recovery_executed_events: EventHandle<AssetRecoveryExecutedEvent>,
    }
    
    /// Token role granted event
    struct TokenRoleGrantedEvent has store, drop {
        token_address: address,
        user: address,
        role_type: u8,
        granted_by: address,
        granted_at: u64,
    }
    
    /// Token role revoked event
    struct TokenRoleRevokedEvent has store, drop {
        token_address: address,
        user: address,
        role_type: u8,
        revoked_by: address,
        revoked_at: u64,
    }
    
    /// Account frozen event
    struct AccountFrozenEvent has store, drop {
        token_address: address,
        account: address,
        frozen_by: address,
        freeze_reason: String,
        frozen_at: u64,
    }
    
    /// Account unfrozen event
    struct AccountUnfrozenEvent has store, drop {
        token_address: address,
        account: address,
        unfrozen_by: address,
        unfrozen_at: u64,
    }
    
    /// Asset recovery requested event
    struct AssetRecoveryRequestedEvent has store, drop {
        token_address: address,
        recovery_id: u64,
        from_account: address,
        to_account: address,
        amount: u64,
        recovery_reason: String,
        requested_by: address,
        requested_at: u64,
    }
    
    /// Asset recovery approved event
    struct AssetRecoveryApprovedEvent has store, drop {
        token_address: address,
        recovery_id: u64,
        approved_by: address,
        approved_at: u64,
        remaining_approvals: u64,
    }
    
    /// Asset recovery executed event
    struct AssetRecoveryExecutedEvent has store, drop {
        token_address: address,
        recovery_id: u64,
        from_account: address,
        to_account: address,
        amount: u64,
        executed_by: address,
        executed_at: u64,
    }

    // ========== INITIALIZATION ==========
    
    /// Initialize token roles registry
    public fun initialize(account: &signer) {
        let account_addr = signer::address_of(account);
        
        // Ensure account is not already initialized
        assert!(!exists<TokenRolesRegistry>(account_addr), constants::get_access_control_not_authorized_error());
        
        let registry = TokenRolesRegistry {
            token_roles: table::new(),
            account_freezes: table::new(),
            asset_recoveries: table::new(),
            next_recovery_id: 1,
            role_granted_events: account::new_event_handle<TokenRoleGrantedEvent>(account),
            role_revoked_events: account::new_event_handle<TokenRoleRevokedEvent>(account),
            account_frozen_events: account::new_event_handle<AccountFrozenEvent>(account),
            account_unfrozen_events: account::new_event_handle<AccountUnfrozenEvent>(account),
            asset_recovery_requested_events: account::new_event_handle<AssetRecoveryRequestedEvent>(account),
            asset_recovery_approved_events: account::new_event_handle<AssetRecoveryApprovedEvent>(account),
            asset_recovery_executed_events: account::new_event_handle<AssetRecoveryExecutedEvent>(account),
        };
        
        move_to(account, registry);
    }

    // ========== TOKEN ROLE MANAGEMENT ==========
    
    /// Grant token role to user
    public fun grant_token_role(
        account: &signer,
        token_address: address,
        user: address,
        role_type: u8,
        permissions: vector<u8>,
        expires_at: u64
    ) acquires TokenRolesRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TokenRolesRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Validate role type
        assert!(constants::is_valid_role_type(role_type), constants::get_invalid_parameter_error());
        
        // Check if user already has this role
        assert!(!has_token_role_internal(registry, token_address, user, role_type), constants::get_access_control_not_authorized_error());
        
        let role_info = TokenRoleInfo {
            role_type,
            user,
            granted_by: account_addr,
            granted_at: current_time,
            expires_at,
            is_active: true,
            permissions,
        };
        
        // Add role to token roles
        if (!table::contains(&registry.token_roles, token_address)) {
            table::add(&mut registry.token_roles, token_address, table::new());
        };
        let token_roles = table::borrow_mut(&mut registry.token_roles, token_address);
        table::add(token_roles, user, role_info);
        
        // Emit event
        event::emit_event(&mut registry.role_granted_events, TokenRoleGrantedEvent {
            token_address,
            user,
            role_type,
            granted_by: account_addr,
            granted_at: current_time,
        });
    }
    
    /// Revoke token role from user
    public fun revoke_token_role(
        account: &signer,
        token_address: address,
        user: address,
        role_type: u8
    ) acquires TokenRolesRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TokenRolesRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if user has this role
        assert!(has_token_role_internal(registry, token_address, user, role_type), constants::get_access_control_not_authorized_error());
        
        // Remove role from token roles
        let token_roles = table::borrow_mut(&mut registry.token_roles, token_address);
        table::remove(token_roles, user);
        
        // Emit event
        event::emit_event(&mut registry.role_revoked_events, TokenRoleRevokedEvent {
            token_address,
            user,
            role_type,
            revoked_by: account_addr,
            revoked_at: current_time,
        });
    }
    
    /// Update token role permissions
    public fun update_token_role_permissions(
        account: &signer,
        token_address: address,
        user: address,
        new_permissions: vector<u8>
    ) acquires TokenRolesRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TokenRolesRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if user has a role
        assert!(table::contains(&registry.token_roles, token_address), constants::get_access_control_not_authorized_error());
        let token_roles = table::borrow(&registry.token_roles, token_address);
        assert!(table::contains(token_roles, user), constants::get_access_control_not_authorized_error());
        
        let token_roles_mut = table::borrow_mut(&mut registry.token_roles, token_address);
        let role_info = table::borrow_mut(token_roles_mut, user);
        role_info.permissions = new_permissions;
    }

    // ========== ACCOUNT FREEZE MANAGEMENT ==========
    
    /// Freeze account
    public fun freeze_account(
        account: &signer,
        token_address: address,
        target_account: address,
        freeze_reason: String
    ) acquires TokenRolesRegistry {
        let freezer = signer::address_of(account);
        let registry = borrow_global_mut<TokenRolesRegistry>(freezer);
        let current_time = timestamp::now_seconds();
        
        // Check if freezer has freeze permission
        assert!(has_token_role_internal(registry, token_address, freezer, constants::get_role_compliance_officer()), constants::get_access_control_not_authorized_error());
        
        let freeze_info = AccountFreezeInfo {
            is_frozen: true,
            freeze_reason,
            frozen_by: freezer,
            frozen_at: current_time,
            is_partially_frozen: false,
            partial_freeze_permissions: vector::empty(),
        };
        
        // Add freeze info to account freezes
        if (!table::contains(&registry.account_freezes, token_address)) {
            table::add(&mut registry.account_freezes, token_address, table::new());
        };
        let account_freezes = table::borrow_mut(&mut registry.account_freezes, token_address);
        table::add(account_freezes, target_account, freeze_info);
        
        // Emit event
        event::emit_event(&mut registry.account_frozen_events, AccountFrozenEvent {
            token_address,
            account: target_account,
            frozen_by: freezer,
            freeze_reason,
            frozen_at: current_time,
        });
    }
    
    /// Unfreeze account
    public fun unfreeze_account(
        account: &signer,
        token_address: address,
        target_account: address
    ) acquires TokenRolesRegistry {
        let unfreezer = signer::address_of(account);
        let registry = borrow_global_mut<TokenRolesRegistry>(unfreezer);
        let current_time = timestamp::now_seconds();
        
        // Check if unfreezer has freeze permission
        assert!(has_token_role_internal(registry, token_address, unfreezer, constants::get_role_compliance_officer()), constants::get_access_control_not_authorized_error());
        
        // Check if account is frozen
        assert!(table::contains(&registry.account_freezes, token_address), constants::get_token_account_frozen_error());
        let account_freezes = table::borrow(&registry.account_freezes, token_address);
        assert!(table::contains(account_freezes, target_account), constants::get_token_account_frozen_error());
        
        // Remove freeze info
        let account_freezes_mut = table::borrow_mut(&mut registry.account_freezes, token_address);
        table::remove(account_freezes_mut, target_account);
        
        // Emit event
        event::emit_event(&mut registry.account_unfrozen_events, AccountUnfrozenEvent {
            token_address,
            account: target_account,
            unfrozen_by: unfreezer,
            unfrozen_at: current_time,
        });
    }
    
    /// Partially freeze account
    public fun partially_freeze_account(
        account: &signer,
        token_address: address,
        target_account: address,
        freeze_reason: String,
        partial_freeze_permissions: vector<u8>
    ) acquires TokenRolesRegistry {
        let freezer = signer::address_of(account);
        let registry = borrow_global_mut<TokenRolesRegistry>(freezer);
        let current_time = timestamp::now_seconds();
        
        // Check if freezer has freeze permission
        assert!(has_token_role_internal(registry, token_address, freezer, constants::get_role_compliance_officer()), constants::get_access_control_not_authorized_error());
        
        let freeze_info = AccountFreezeInfo {
            is_frozen: false,
            freeze_reason,
            frozen_by: freezer,
            frozen_at: current_time,
            is_partially_frozen: true,
            partial_freeze_permissions,
        };
        
        // Add freeze info to account freezes
        if (!table::contains(&registry.account_freezes, token_address)) {
            table::add(&mut registry.account_freezes, token_address, table::new());
        };
        let account_freezes = table::borrow_mut(&mut registry.account_freezes, token_address);
        table::add(account_freezes, target_account, freeze_info);
        
        // Emit event
        event::emit_event(&mut registry.account_frozen_events, AccountFrozenEvent {
            token_address,
            account: target_account,
            frozen_by: freezer,
            freeze_reason,
            frozen_at: current_time,
        });
    }

    // ========== ASSET RECOVERY MANAGEMENT ==========
    
    /// Request asset recovery
    public fun request_asset_recovery(
        account: &signer,
        token_address: address,
        from_account: address,
        to_account: address,
        amount: u64,
        recovery_reason: String,
        required_approvals: u64
    ): u64 acquires TokenRolesRegistry {
        let requester = signer::address_of(account);
        let registry = borrow_global_mut<TokenRolesRegistry>(requester);
        let current_time = timestamp::now_seconds();
        
        // Check if requester has recovery permission
        assert!(has_token_role_internal(registry, token_address, requester, constants::get_role_compliance_officer()), constants::get_access_control_not_authorized_error());
        
        // Validate parameters
        assert!(constants::is_valid_amount(amount), constants::get_invalid_parameter_error());
        assert!(required_approvals > 0, constants::get_invalid_parameter_error());
        
        let recovery_id = registry.next_recovery_id;
        registry.next_recovery_id = registry.next_recovery_id + 1;
        
        let recovery_info = AssetRecoveryInfo {
            recovery_id,
            from_account,
            to_account,
            amount,
            recovery_reason,
            requested_by: requester,
            requested_at: current_time,
            approved_by: vector::empty(),
            required_approvals,
            status: 1, // Pending
            executed_at: 0,
        };
        
        // Add recovery info to asset recoveries
        if (!table::contains(&registry.asset_recoveries, token_address)) {
            table::add(&mut registry.asset_recoveries, token_address, table::new());
        };
        let asset_recoveries = table::borrow_mut(&mut registry.asset_recoveries, token_address);
        table::add(asset_recoveries, recovery_id, recovery_info);
        
        // Emit event
        event::emit_event(&mut registry.asset_recovery_requested_events, AssetRecoveryRequestedEvent {
            token_address,
            recovery_id,
            from_account,
            to_account,
            amount,
            recovery_reason,
            requested_by: requester,
            requested_at: current_time,
        });
        
        recovery_id
    }
    
    /// Approve asset recovery
    public fun approve_asset_recovery(
        account: &signer,
        token_address: address,
        recovery_id: u64
    ) acquires TokenRolesRegistry {
        let approver = signer::address_of(account);
        let registry = borrow_global_mut<TokenRolesRegistry>(approver);
        let current_time = timestamp::now_seconds();
        
        // Check if approver has recovery permission
        assert!(has_token_role_internal(registry, token_address, approver, constants::get_role_compliance_officer()), constants::get_access_control_not_authorized_error());
        
        // Check if recovery exists
        assert!(table::contains(&registry.asset_recoveries, token_address), constants::get_token_recovery_not_authorized_error());
        let asset_recoveries = table::borrow(&registry.asset_recoveries, token_address);
        assert!(table::contains(asset_recoveries, recovery_id), constants::get_token_recovery_not_authorized_error());
        
        let asset_recoveries_mut = table::borrow_mut(&mut registry.asset_recoveries, token_address);
        let recovery_info = table::borrow_mut(asset_recoveries_mut, recovery_id);
        
        // Check if recovery is pending
        assert!(recovery_info.status == 1, constants::get_token_recovery_not_authorized_error());
        
        // Check if approver has already approved
        let (found, _) = find_user_index(&recovery_info.approved_by, approver);
        assert!(!found, constants::get_token_recovery_not_authorized_error());
        
        // Add approver to approved list
        vector::push_back(&mut recovery_info.approved_by, approver);
        
        // Check if enough approvals
        if (vector::length(&recovery_info.approved_by) >= recovery_info.required_approvals) {
            recovery_info.status = 2; // Approved
        };
        
        // Emit event
        event::emit_event(&mut registry.asset_recovery_approved_events, AssetRecoveryApprovedEvent {
            token_address,
            recovery_id,
            approved_by: approver,
            approved_at: current_time,
            remaining_approvals: recovery_info.required_approvals - vector::length(&recovery_info.approved_by),
        });
    }
    
    /// Execute asset recovery
    public fun execute_asset_recovery(
        account: &signer,
        token_address: address,
        recovery_id: u64
    ) acquires TokenRolesRegistry {
        let executor = signer::address_of(account);
        let registry = borrow_global_mut<TokenRolesRegistry>(executor);
        let current_time = timestamp::now_seconds();
        
        // Check if executor has recovery permission
        assert!(has_token_role_internal(registry, token_address, executor, constants::get_role_compliance_officer()), constants::get_access_control_not_authorized_error());
        
        // Check if recovery exists
        assert!(table::contains(&registry.asset_recoveries, token_address), constants::get_token_recovery_not_authorized_error());
        let asset_recoveries = table::borrow(&registry.asset_recoveries, token_address);
        assert!(table::contains(asset_recoveries, recovery_id), constants::get_token_recovery_not_authorized_error());
        
        let asset_recoveries_mut = table::borrow_mut(&mut registry.asset_recoveries, token_address);
        let recovery_info = table::borrow_mut(asset_recoveries_mut, recovery_id);
        
        // Check if recovery is approved
        assert!(recovery_info.status == 2, constants::get_token_recovery_not_authorized_error());
        
        // Update recovery status
        recovery_info.status = 3; // Executed
        recovery_info.executed_at = current_time;
        
        // Emit event
        event::emit_event(&mut registry.asset_recovery_executed_events, AssetRecoveryExecutedEvent {
            token_address,
            recovery_id,
            from_account: recovery_info.from_account,
            to_account: recovery_info.to_account,
            amount: recovery_info.amount,
            executed_by: executor,
            executed_at: current_time,
        });
    }

    // ========== VIEW FUNCTIONS ==========
    
    /// Check if user has token role
    public fun has_token_role(token_address: address, user: address, role_type: u8): bool acquires TokenRolesRegistry {
        let registry = borrow_global<TokenRolesRegistry>(user);
        has_token_role_internal(registry, token_address, user, role_type)
    }
    
    /// Check if user has token role (internal)
    fun has_token_role_internal(registry: &TokenRolesRegistry, token_address: address, user: address, role_type: u8): bool {
        if (!table::contains(&registry.token_roles, token_address)) {
            return false
        };
        
        let token_roles = table::borrow(&registry.token_roles, token_address);
        if (!table::contains(token_roles, user)) {
            return false
        };
        
        let role_info = table::borrow(token_roles, user);
        role_info.role_type == role_type && role_info.is_active
    }
    
    /// Get user's token roles
    public fun get_user_token_roles(token_address: address, user: address): vector<u8> acquires TokenRolesRegistry {
        let registry = borrow_global<TokenRolesRegistry>(user);
        let roles = vector::empty();
        
        if (table::contains(&registry.token_roles, token_address)) {
            let token_roles = table::borrow(&registry.token_roles, token_address);
            if (table::contains(token_roles, user)) {
                let role_info = table::borrow(token_roles, user);
                if (role_info.is_active) {
                    vector::push_back(&mut roles, role_info.role_type);
                };
            };
        };
        
        roles
    }
    
    /// Check if account is frozen
    public fun is_account_frozen(token_address: address, account: address): bool acquires TokenRolesRegistry {
        // Registry is stored at the admin address, not the user address
        // Note: This function needs admin address to access registry
        // For now, we'll use a placeholder - this needs to be refactored
        let registry = borrow_global<TokenRolesRegistry>(@0x1);
        
        if (!table::contains(&registry.account_freezes, token_address)) {
            return false
        };
        
        let account_freezes = table::borrow(&registry.account_freezes, token_address);
        if (!table::contains(account_freezes, account)) {
            return false
        };
        
        let freeze_info = table::borrow(account_freezes, account);
        freeze_info.is_frozen
    }
    
    /// Check if account is partially frozen
    public fun is_account_partially_frozen(token_address: address, account: address): bool acquires TokenRolesRegistry {
        let registry = borrow_global<TokenRolesRegistry>(account);
        
        if (!table::contains(&registry.account_freezes, token_address)) {
            return false
        };
        
        let account_freezes = table::borrow(&registry.account_freezes, token_address);
        if (!table::contains(account_freezes, account)) {
            return false
        };
        
        let freeze_info = table::borrow(account_freezes, account);
        freeze_info.is_partially_frozen
    }
    
    /// Get account freeze information
    public fun get_account_freeze_info(token_address: address, account: address): (bool, String, address, u64, bool, vector<u8>) acquires TokenRolesRegistry {
        let registry = borrow_global<TokenRolesRegistry>(account);
        
        if (!table::contains(&registry.account_freezes, token_address)) {
            return (false, string::utf8(b""), @0x0, 0, false, vector::empty())
        };
        
        let account_freezes = table::borrow(&registry.account_freezes, token_address);
        if (!table::contains(account_freezes, account)) {
            return (false, string::utf8(b""), @0x0, 0, false, vector::empty())
        };
        
        let freeze_info = table::borrow(account_freezes, account);
        (
            freeze_info.is_frozen,
            freeze_info.freeze_reason,
            freeze_info.frozen_by,
            freeze_info.frozen_at,
            freeze_info.is_partially_frozen,
            freeze_info.partial_freeze_permissions,
        )
    }
    
    /// Get asset recovery information
    public fun get_asset_recovery_info(token_address: address, recovery_id: u64): (address, address, u64, String, address, u64, vector<address>, u64, u8, u64) acquires TokenRolesRegistry {
        let registry = borrow_global<TokenRolesRegistry>(@0x0); // This will need to be updated with actual address
        assert!(table::contains(&registry.asset_recoveries, token_address), constants::get_token_recovery_not_authorized_error());
        
        let asset_recoveries = table::borrow(&registry.asset_recoveries, token_address);
        assert!(table::contains(asset_recoveries, recovery_id), constants::get_token_recovery_not_authorized_error());
        
        let recovery_info = table::borrow(asset_recoveries, recovery_id);
        (
            recovery_info.from_account,
            recovery_info.to_account,
            recovery_info.amount,
            recovery_info.recovery_reason,
            recovery_info.requested_by,
            recovery_info.requested_at,
            recovery_info.approved_by,
            recovery_info.required_approvals,
            recovery_info.status,
            recovery_info.executed_at,
        )
    }
    
    /// Check if user can perform action
    public fun can_user_perform_action(token_address: address, user: address, action: u8): bool acquires TokenRolesRegistry {
        let registry = borrow_global<TokenRolesRegistry>(user);
        
        if (!table::contains(&registry.token_roles, token_address)) {
            return false
        };
        
        let token_roles = table::borrow(&registry.token_roles, token_address);
        if (!table::contains(token_roles, user)) {
            return false
        };
        
        let role_info = table::borrow(token_roles, user);
        if (!role_info.is_active) {
            return false
        };
        
        // Check if role has expired
        if (role_info.expires_at > 0) {
            let current_time = timestamp::now_seconds();
            if (current_time > role_info.expires_at) {
                return false
            };
        };
        
        // Check permissions
        let (found, _) = find_permission_index(&role_info.permissions, action);
        found
    }

    // ========== HELPER FUNCTIONS ==========
    
    /// Find user index in approved by vector
    fun find_user_index(approved_by: &vector<address>, user: address): (bool, u64) {
        let len = vector::length(approved_by);
        let i = 0;
        while (i < len) {
            let approved_user = *vector::borrow(approved_by, i);
            if (approved_user == user) {
                return (true, i)
            };
            i = i + 1;
        };
        (false, 0)
    }
    
    /// Find permission index in permissions vector
    fun find_permission_index(permissions: &vector<u8>, action: u8): (bool, u64) {
        let len = vector::length(permissions);
        let i = 0;
        while (i < len) {
            let permission = *vector::borrow(permissions, i);
            if (permission == action) {
                return (true, i)
            };
            i = i + 1;
        };
        (false, 0)
    }
}
