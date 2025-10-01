/// Onchain Identity module for T-REX compliant token system
/// Main interface for identity management and claim verification

module FARE::onchain_identity {
    use std::vector;
    use std::string::{Self, String};
    use std::table::{Self, Table};
    use std::error;
    use std::signer;
    use std::timestamp;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;
    use FARE::constants;
    use FARE::identity_storage::{Self, Identity, IdentityClaim, IdentityMetadata, IdentityRecovery};
    use FARE::claim_issuers;

    // ========== STRUCTS ==========
    
    /// Identity registry for managing all identities
    struct IdentityRegistry has key {
        /// Map of user address to user address (simplified)
        user_identities: Table<address, address>,
        /// Total number of identities
        total_identities: u64,
        /// Events
        identity_created_events: EventHandle<IdentityCreatedEvent>,
        identity_updated_events: EventHandle<IdentityUpdatedEvent>,
        identity_deleted_events: EventHandle<IdentityDeletedEvent>,
    }
    
    /// Identity created event
    struct IdentityCreatedEvent has store, drop {
        user: address,
        identity: address,
        created_at: u64,
    }
    
    /// Identity updated event
    struct IdentityUpdatedEvent has store, drop {
        user: address,
        identity: address,
        updated_at: u64,
    }
    
    /// Identity deleted event
    struct IdentityDeletedEvent has store, drop {
        user: address,
        deleted_at: u64,
    }

    // ========== INITIALIZATION ==========
    
    /// Initialize identity registry
    public fun initialize(account: &signer) {
        let account_addr = signer::address_of(account);
        
        // Ensure account is not already initialized
        assert!(!exists<IdentityRegistry>(account_addr), constants::get_access_control_not_authorized_error());
        
        let registry = IdentityRegistry {
            user_identities: table::new(),
            total_identities: 0,
            identity_created_events: account::new_event_handle<IdentityCreatedEvent>(account),
            identity_updated_events: account::new_event_handle<IdentityUpdatedEvent>(account),
            identity_deleted_events: account::new_event_handle<IdentityDeletedEvent>(account),
        };
        
        move_to(account, registry);
    }

    // ========== IDENTITY CREATION ==========
    
    /// Create a new identity for a user
    public fun create_identity(
        account: &signer,
        kyc_level: u8,
        investor_type: u8,
        country_code: vector<u8>,
        date_of_birth: u64
    ) acquires IdentityRegistry {
        let account_addr = signer::address_of(account);
        // Registry is stored at the admin address, not the user address
        let registry = borrow_global_mut<IdentityRegistry>(@0x1);
        let current_time = timestamp::now_seconds();
        
        // Check if user already has an identity
        assert!(!table::contains(&registry.user_identities, account_addr), constants::get_identity_already_exists_error());
        
        // Create identity
        identity_storage::create_identity(
            account,
            kyc_level,
            investor_type,
            country_code,
            date_of_birth
        );
        
        // Register identity in registry
        table::add(&mut registry.user_identities, account_addr, account_addr);
        registry.total_identities = registry.total_identities + 1;
        
        // Emit event
        event::emit_event(&mut registry.identity_created_events, IdentityCreatedEvent {
            user: account_addr,
            identity: account_addr,
            created_at: current_time,
        });
    }
    
    /// Delete an identity
    public fun delete_identity(
        account: &signer,
        user: address
    ) acquires IdentityRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<IdentityRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if identity exists
        assert!(table::contains(&registry.user_identities, user), constants::get_identity_not_found_error());
        
        // Check if user is the owner
        assert!(user == account_addr, constants::get_access_control_not_authorized_error());
        
        // Remove from registry
        table::remove(&mut registry.user_identities, user);
        registry.total_identities = registry.total_identities - 1;
        
        // Emit event
        event::emit_event(&mut registry.identity_deleted_events, IdentityDeletedEvent {
            user,
            deleted_at: current_time,
        });

        // Remove identity from storage
        identity_storage::delete_identity_internal(user);
    }

    // ========== CLAIM MANAGEMENT ==========
    
    /// Add a claim to user's identity
    public fun add_claim(
        account: &signer,
        user: address,
        topic: u256,
        scheme: u8,
        signature: vector<u8>,
        data: vector<u8>,
        uri: String,
        expiration_date: u64
    ) acquires IdentityRegistry {
        let issuer = signer::address_of(account);
        let registry = borrow_global<IdentityRegistry>(issuer);
        
        // Check if user has an identity
        assert!(table::contains(&registry.user_identities, user), constants::get_identity_not_found_error());
        
        // Check if issuer is authorized to issue this claim
        assert!(claim_issuers::can_issuer_issue_claim(issuer, topic), constants::get_identity_claim_issuer_not_authorized_error());
        
        // Check if issuer has not reached daily limit
        assert!(!claim_issuers::has_issuer_reached_daily_limit(issuer), constants::get_identity_claim_issuer_not_authorized_error());
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        
        // Add claim to identity
        identity_storage::add_claim(
            account,
            topic,
            scheme,
            issuer,
            signature,
            data,
            uri,
            expiration_date
        );
        
        // Update registry
        let registry_mut = borrow_global_mut<IdentityRegistry>(issuer);
        event::emit_event(&mut registry_mut.identity_updated_events, IdentityUpdatedEvent {
            user,
            identity: identity_object,
            updated_at: timestamp::now_seconds(),
        });
    }
    
    /// Revoke a claim from user's identity
    public fun revoke_claim(
        account: &signer,
        user: address,
        topic: u256
    ) acquires IdentityRegistry {
        let issuer = signer::address_of(account);
        let registry = borrow_global<IdentityRegistry>(issuer);
        
        // Check if user has an identity
        assert!(table::contains(&registry.user_identities, user), constants::get_identity_not_found_error());
        
        // Check if issuer is authorized to revoke claims
        let (_, _, _, _, _, can_revoke) = claim_issuers::get_issuer_permissions(issuer);
        assert!(can_revoke, constants::get_identity_claim_issuer_not_authorized_error());
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        
        // Revoke claim from identity
        identity_storage::revoke_claim(account, topic, issuer);
        
        // Update registry
        let registry_mut = borrow_global_mut<IdentityRegistry>(issuer);
        event::emit_event(&mut registry_mut.identity_updated_events, IdentityUpdatedEvent {
            user,
            identity: identity_object,
            updated_at: timestamp::now_seconds(),
        });
    }
    
    /// Update claim data
    public fun update_claim(
        account: &signer,
        user: address,
        topic: u256,
        new_data: vector<u8>,
        new_uri: String
    ) acquires IdentityRegistry {
        let issuer = signer::address_of(account);
        let registry = borrow_global<IdentityRegistry>(issuer);
        
        // Check if user has an identity
        assert!(table::contains(&registry.user_identities, user), constants::get_identity_not_found_error());
        
        // Check if issuer is authorized to issue this claim
        assert!(claim_issuers::can_issuer_issue_claim(issuer, topic), constants::get_identity_claim_issuer_not_authorized_error());
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        
        // Update claim in identity
        identity_storage::update_claim(account, topic, new_data, new_uri);
        
        // Update registry
        let registry_mut = borrow_global_mut<IdentityRegistry>(issuer);
        event::emit_event(&mut registry_mut.identity_updated_events, IdentityUpdatedEvent {
            user,
            identity: identity_object,
            updated_at: timestamp::now_seconds(),
        });
    }

    // ========== METADATA MANAGEMENT ==========
    
    /// Update user's identity metadata
    public fun update_metadata(
        account: &signer,
        user: address,
        kyc_level: u8,
        investor_type: u8,
        age_verified: bool,
        pep_status: bool,
        sanctions_checked: bool,
        country_code: vector<u8>
    ) acquires IdentityRegistry {
        let issuer = signer::address_of(account);
        let registry = borrow_global<IdentityRegistry>(issuer);
        
        // Check if user has an identity
        assert!(table::contains(&registry.user_identities, user), constants::get_identity_not_found_error());
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        
        // Update metadata in identity
        identity_storage::update_metadata(
            account,
            kyc_level,
            investor_type,
            age_verified,
            pep_status,
            sanctions_checked,
            country_code
        );
        
        // Update registry
        let registry_mut = borrow_global_mut<IdentityRegistry>(issuer);
        event::emit_event(&mut registry_mut.identity_updated_events, IdentityUpdatedEvent {
            user,
            identity: identity_object,
            updated_at: timestamp::now_seconds(),
        });
    }
    
    /// Update KYC level
    public fun update_kyc_level(
        account: &signer,
        user: address,
        kyc_level: u8
    ) acquires IdentityRegistry {
        let issuer = signer::address_of(account);
        let registry = borrow_global<IdentityRegistry>(issuer);
        
        // Check if user has an identity
        assert!(table::contains(&registry.user_identities, user), constants::get_identity_not_found_error());
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        
        // Update KYC level in identity
        identity_storage::update_kyc_level(account, kyc_level);
        
        // Update registry
        let registry_mut = borrow_global_mut<IdentityRegistry>(issuer);
        event::emit_event(&mut registry_mut.identity_updated_events, IdentityUpdatedEvent {
            user,
            identity: identity_object,
            updated_at: timestamp::now_seconds(),
        });
    }
    
    /// Update investor type
    public fun update_investor_type(
        account: &signer,
        user: address,
        investor_type: u8
    ) acquires IdentityRegistry {
        let issuer = signer::address_of(account);
        let registry = borrow_global<IdentityRegistry>(issuer);
        
        // Check if user has an identity
        assert!(table::contains(&registry.user_identities, user), constants::get_identity_not_found_error());
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        
        // Update investor type in identity
        identity_storage::update_investor_type(account, investor_type);
        
        // Update registry
        let registry_mut = borrow_global_mut<IdentityRegistry>(issuer);
        event::emit_event(&mut registry_mut.identity_updated_events, IdentityUpdatedEvent {
            user,
            identity: identity_object,
            updated_at: timestamp::now_seconds(),
        });
    }

    // ========== RECOVERY MANAGEMENT ==========
    
    /// Set up identity recovery
    public fun setup_recovery(
        account: &signer,
        recovery_addresses: vector<address>,
        recovery_threshold: u64,
        recovery_delay: u64
    ) acquires IdentityRegistry {
        let user = signer::address_of(account);
        let registry = borrow_global<IdentityRegistry>(user);
        
        // Check if user has an identity
        assert!(table::contains(&registry.user_identities, user), constants::get_identity_not_found_error());
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        
        // Set up recovery in identity
        identity_storage::setup_recovery(account, recovery_addresses, recovery_threshold, recovery_delay);
        
        // Update registry
        let registry_mut = borrow_global_mut<IdentityRegistry>(user);
        event::emit_event(&mut registry_mut.identity_updated_events, IdentityUpdatedEvent {
            user,
            identity: identity_object,
            updated_at: timestamp::now_seconds(),
        });
    }
    
    /// Execute identity recovery
    public fun execute_recovery(
        account: &signer,
        old_owner: address,
        new_owner: address,
        recovery_signatures: vector<vector<u8>>
    ) acquires IdentityRegistry {
        let registry = borrow_global<IdentityRegistry>(old_owner);
        
        // Check if old owner has an identity
        assert!(table::contains(&registry.user_identities, old_owner), constants::get_identity_not_found_error());
        
        let identity_object = *table::borrow(&registry.user_identities, old_owner);
        
        // Execute recovery in identity
        identity_storage::execute_recovery(account, new_owner, recovery_signatures);
        
        // Update registry
        let registry_mut = borrow_global_mut<IdentityRegistry>(old_owner);
        table::remove(&mut registry_mut.user_identities, old_owner);
        table::add(&mut registry_mut.user_identities, new_owner, new_owner);
        
        event::emit_event(&mut registry_mut.identity_updated_events, IdentityUpdatedEvent {
            user: new_owner,
            identity: new_owner,
            updated_at: timestamp::now_seconds(),
        });
    }

    // ========== FREEZE/UNFREEZE ==========
    
    /// Freeze user's identity
    public fun freeze_identity(
        account: &signer,
        user: address,
        freeze_reason: String
    ) acquires IdentityRegistry {
        let freezer = signer::address_of(account);
        let registry = borrow_global<IdentityRegistry>(freezer);
        
        // Check if user has an identity
        assert!(table::contains(&registry.user_identities, user), constants::get_identity_not_found_error());
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        
        // Freeze identity
        identity_storage::freeze_identity(account, freeze_reason);
        
        // Update registry
        let registry_mut = borrow_global_mut<IdentityRegistry>(freezer);
        event::emit_event(&mut registry_mut.identity_updated_events, IdentityUpdatedEvent {
            user,
            identity: identity_object,
            updated_at: timestamp::now_seconds(),
        });
    }
    
    /// Unfreeze user's identity
    public fun unfreeze_identity(
        account: &signer,
        user: address
    ) acquires IdentityRegistry {
        let unfreezer = signer::address_of(account);
        let registry = borrow_global<IdentityRegistry>(unfreezer);
        
        // Check if user has an identity
        assert!(table::contains(&registry.user_identities, user), constants::get_identity_not_found_error());
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        
        // Unfreeze identity
        identity_storage::unfreeze_identity(account);
        
        // Update registry
        let registry_mut = borrow_global_mut<IdentityRegistry>(unfreezer);
        event::emit_event(&mut registry_mut.identity_updated_events, IdentityUpdatedEvent {
            user,
            identity: identity_object,
            updated_at: timestamp::now_seconds(),
        });
    }

    // ========== VIEW FUNCTIONS ==========
    
    /// Check if user has an identity
    public fun has_identity(user: address): bool acquires IdentityRegistry {
        // Registry is stored at the admin address, not the user address
        let registry = borrow_global<IdentityRegistry>(@0x1);
        table::contains(&registry.user_identities, user)
    }
    
    /// Get user's identity object
    public fun get_identity_object(user: address): address acquires IdentityRegistry {
        let registry = borrow_global<IdentityRegistry>(user);
        assert!(table::contains(&registry.user_identities, user), constants::get_identity_not_found_error());
        user
    }
    
    /// Get identity status
    public fun get_identity_status(user: address): (bool, u8, u8, bool, bool, bool, vector<u8>) acquires IdentityRegistry {
        // Registry is stored at the admin address, not the user address
        let registry = borrow_global<IdentityRegistry>(@0x1);
        
        if (!table::contains(&registry.user_identities, user)) {
            return (false, 0, 0, false, false, false, vector::empty())
        };
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        let (kyc_level, investor_type, age_verified, pep_status, sanctions_checked, country_code, _, _) = 
            identity_storage::get_identity_metadata(user);
        
        (true, kyc_level, investor_type, age_verified, pep_status, sanctions_checked, country_code)
    }
    
    /// Check if user's identity is frozen
    public fun is_identity_frozen(user: address): bool acquires IdentityRegistry {
        let registry = borrow_global<IdentityRegistry>(user);
        
        if (!table::contains(&registry.user_identities, user)) {
            return false
        };
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        identity_storage::is_identity_frozen(user)
    }
    
    /// Get identity metadata
    public fun get_identity_metadata(user: address): (u8, u8, bool, bool, bool, vector<u8>, u64, u64) acquires IdentityRegistry {
        let registry = borrow_global<IdentityRegistry>(user);
        assert!(table::contains(&registry.user_identities, user), constants::get_identity_not_found_error());
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        identity_storage::get_identity_metadata(user)
    }
    
    /// Get claim information
    public fun get_claim(user: address, topic: u256): (u8, address, vector<u8>, vector<u8>, String, u64, u64, bool) acquires IdentityRegistry {
        let registry = borrow_global<IdentityRegistry>(user);
        assert!(table::contains(&registry.user_identities, user), constants::get_identity_not_found_error());
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        identity_storage::get_claim(user, topic)
    }
    
    /// Check if claim exists and is valid
    public fun is_claim_valid(user: address, topic: u256): bool acquires IdentityRegistry {
        let registry = borrow_global<IdentityRegistry>(user);
        
        if (!table::contains(&registry.user_identities, user)) {
            return false
        };
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        identity_storage::is_claim_valid(user, topic)
    }
    
    /// Get all claim topics for user
    public fun get_claim_topics(user: address): vector<u256> acquires IdentityRegistry {
        let registry = borrow_global<IdentityRegistry>(user);
        
        if (!table::contains(&registry.user_identities, user)) {
            return vector::empty()
        };
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        identity_storage::get_claim_topics(user)
    }
    
    /// Get recovery information
    public fun get_recovery_info(user: address): (vector<address>, u64, u64, bool) acquires IdentityRegistry {
        let registry = borrow_global<IdentityRegistry>(user);
        assert!(table::contains(&registry.user_identities, user), constants::get_identity_not_found_error());
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        identity_storage::get_recovery_info(user)
    }
    
    /// Get identity creation and update timestamps
    public fun get_identity_timestamps(user: address): (u64, u64) acquires IdentityRegistry {
        let registry = borrow_global<IdentityRegistry>(user);
        assert!(table::contains(&registry.user_identities, user), constants::get_identity_not_found_error());
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        identity_storage::get_identity_timestamps(user)
    }
    
    /// Get freeze information
    public fun get_freeze_info(user: address): (bool, String) acquires IdentityRegistry {
        let registry = borrow_global<IdentityRegistry>(user);
        
        if (!table::contains(&registry.user_identities, user)) {
            return (false, string::utf8(b""))
        };
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        identity_storage::get_freeze_info(user)
    }
    
    /// Get total number of identities
    public fun get_total_identities(): u64 acquires IdentityRegistry {
        let registry = borrow_global<IdentityRegistry>(@0x0); // This will need to be updated with actual address
        registry.total_identities
    }
    
    /// Check if user has specific claim topic
    public fun has_claim_topic(user: address, topic: u256): bool acquires IdentityRegistry {
        let registry = borrow_global<IdentityRegistry>(user);
        
        if (!table::contains(&registry.user_identities, user)) {
            return false
        };
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        identity_storage::is_claim_valid(user, topic)
    }
    
    /// Get user's KYC level
    public fun get_kyc_level(user: address): u8 acquires IdentityRegistry {
        // Registry is stored at the admin address, not the user address
        let registry = borrow_global<IdentityRegistry>(@0x1);
        
        if (!table::contains(&registry.user_identities, user)) {
            return constants::get_kyc_level_none()
        };
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        let (kyc_level, _, _, _, _, _, _, _) = identity_storage::get_identity_metadata(user);
        kyc_level
    }
    
    /// Get user's investor type
    public fun get_investor_type(user: address): u8 acquires IdentityRegistry {
        // Registry is stored at the admin address, not the user address
        let registry = borrow_global<IdentityRegistry>(@0x1);
        
        if (!table::contains(&registry.user_identities, user)) {
            return 0
        };
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        let (_, investor_type, _, _, _, _, _, _) = identity_storage::get_identity_metadata(user);
        investor_type
    }
    
    /// Get user's country code
    public fun get_country_code(user: address): vector<u8> acquires IdentityRegistry {
        let registry = borrow_global<IdentityRegistry>(user);
        
        if (!table::contains(&registry.user_identities, user)) {
            return vector::empty()
        };
        
        let identity_object = *table::borrow(&registry.user_identities, user);
        let (_, _, _, _, _, country_code, _, _) = identity_storage::get_identity_metadata(user);
        country_code
    }
}
