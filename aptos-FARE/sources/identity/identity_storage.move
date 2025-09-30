/// Identity Storage module for T-REX compliant token system
/// Provides storage structures and utilities for identity management

module FARE::identity_storage {
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
    
    friend FARE::onchain_identity;

    // ========== STRUCTS ==========
    
    /// Identity claim following ERC-735 standard
    struct IdentityClaim has store, copy, drop {
        /// Claim topic (e.g., KYC, AML, Country)
        topic: u256,
        /// Claim scheme (signature scheme used)
        scheme: u8,
        /// Issuer address
        issuer: address,
        /// Claim signature
        signature: vector<u8>,
        /// Claim data
        data: vector<u8>,
        /// Claim URI for additional information
        uri: String,
        /// Issuance timestamp
        issuance_date: u64,
        /// Expiration timestamp (0 = never expires)
        expiration_date: u64,
        /// Whether claim is active
        is_active: bool,
    }
    
    /// Identity metadata
    struct IdentityMetadata has store, copy, drop {
        /// KYC verification level
        kyc_level: u8,
        /// Investor type
        investor_type: u8,
        /// Age verification status
        age_verified: bool,
        /// PEP (Politically Exposed Person) status
        pep_status: bool,
        /// Sanctions screening status
        sanctions_checked: bool,
        /// Country of residence
        country_code: vector<u8>,
        /// Date of birth (timestamp)
        date_of_birth: u64,
        /// Last updated timestamp
        last_updated: u64,
    }
    
    /// Identity recovery information
    struct IdentityRecovery has store, copy, drop {
        /// Recovery addresses
        recovery_addresses: vector<address>,
        /// Recovery threshold (number of signatures required)
        recovery_threshold: u64,
        /// Recovery delay (time before recovery can be executed)
        recovery_delay: u64,
        /// Whether recovery is active
        is_active: bool,
    }
    
    /// Identity object (non-transferable)
    struct Identity has key {
        /// Identity owner
        owner: address,
        /// Identity claims
        claims: Table<u256, IdentityClaim>,
        /// Identity metadata
        metadata: IdentityMetadata,
        /// Recovery information
        recovery: IdentityRecovery,
        /// Whether identity is frozen
        is_frozen: bool,
        /// Freeze reason
        freeze_reason: String,
        /// Created timestamp
        created_at: u64,
        /// Last updated timestamp
        updated_at: u64,
        /// Events
        claim_added_events: EventHandle<ClaimAddedEvent>,
        claim_revoked_events: EventHandle<ClaimRevokedEvent>,
        identity_frozen_events: EventHandle<IdentityFrozenEvent>,
        identity_unfrozen_events: EventHandle<IdentityUnfrozenEvent>,
        identity_recovered_events: EventHandle<IdentityRecoveredEvent>,
    }
    
    /// Claim added event
    struct ClaimAddedEvent has store, drop {
        identity: address,
        topic: u256,
        issuer: address,
        issuance_date: u64,
        expiration_date: u64,
    }
    
    /// Claim revoked event
    struct ClaimRevokedEvent has store, drop {
        identity: address,
        topic: u256,
        revoked_by: address,
        revoked_at: u64,
    }
    
    /// Identity frozen event
    struct IdentityFrozenEvent has store, drop {
        identity: address,
        frozen_by: address,
        frozen_at: u64,
        freeze_reason: String,
    }
    
    /// Identity unfrozen event
    struct IdentityUnfrozenEvent has store, drop {
        identity: address,
        unfrozen_by: address,
        unfrozen_at: u64,
    }
    
    /// Identity recovered event
    struct IdentityRecoveredEvent has store, drop {
        identity: address,
        old_owner: address,
        new_owner: address,
        recovered_at: u64,
    }

    // ========== INITIALIZATION ==========
    
    /// Create a new identity
    public fun create_identity(
        account: &signer,
        kyc_level: u8,
        investor_type: u8,
        country_code: vector<u8>,
        date_of_birth: u64
    ) {
        let account_addr = signer::address_of(account);
        let current_time = timestamp::now_seconds();
        
        // Validate parameters
        assert!(constants::is_valid_kyc_level(kyc_level), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_investor_type(investor_type), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_country_code(country_code), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_timestamp(date_of_birth), constants::get_invalid_parameter_error());
        
        let identity = Identity {
            owner: account_addr,
            claims: table::new(),
            metadata: IdentityMetadata {
                kyc_level,
                investor_type,
                age_verified: false,
                pep_status: false,
                sanctions_checked: false,
                country_code,
                date_of_birth,
                last_updated: current_time,
            },
            recovery: IdentityRecovery {
                recovery_addresses: vector::empty(),
                recovery_threshold: 1,
                recovery_delay: 0,
                is_active: false,
            },
            is_frozen: false,
            freeze_reason: string::utf8(b""),
            created_at: current_time,
            updated_at: current_time,
            claim_added_events: account::new_event_handle<ClaimAddedEvent>(account),
            claim_revoked_events: account::new_event_handle<ClaimRevokedEvent>(account),
            identity_frozen_events: account::new_event_handle<IdentityFrozenEvent>(account),
            identity_unfrozen_events: account::new_event_handle<IdentityUnfrozenEvent>(account),
            identity_recovered_events: account::new_event_handle<IdentityRecoveredEvent>(account),
        };
        
        move_to(account, identity)
    }

    // ========== CLAIM MANAGEMENT ==========
    
    /// Add a claim to identity
    public fun add_claim(
        account: &signer,
        topic: u256,
        scheme: u8,
        issuer: address,
        signature: vector<u8>,
        data: vector<u8>,
        uri: String,
        expiration_date: u64
    ) acquires Identity {
        let identity = borrow_global_mut<Identity>(signer::address_of(account));
        let current_time = timestamp::now_seconds();
        
        // Check if identity is frozen
        assert!(!identity.is_frozen, constants::get_identity_frozen_error());
        
        // Check if claim already exists
        assert!(!table::contains(&identity.claims, topic), constants::get_identity_claim_already_exists_error());
        
        // Validate expiration date
        if (expiration_date > 0) {
            assert!(expiration_date > current_time, constants::get_identity_claim_invalid_error());
        };
        
        let claim = IdentityClaim {
            topic,
            scheme,
            issuer,
            signature,
            data,
            uri,
            issuance_date: current_time,
            expiration_date,
            is_active: true,
        };
        
        table::add(&mut identity.claims, topic, claim);
        identity.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut identity.claim_added_events, ClaimAddedEvent {
            identity: identity.owner,
            topic,
            issuer,
            issuance_date: current_time,
            expiration_date,
        });
    }
    
    /// Revoke a claim from identity
    public fun revoke_claim(
        account: &signer,
        topic: u256,
        revoked_by: address
    ) acquires Identity {
        let identity = borrow_global_mut<Identity>(signer::address_of(account));
        let current_time = timestamp::now_seconds();
        
        // Check if identity is frozen
        assert!(!identity.is_frozen, constants::get_identity_frozen_error());
        
        // Check if claim exists
        assert!(table::contains(&identity.claims, topic), constants::get_identity_claim_not_found_error());
        
        let claim = table::borrow_mut(&mut identity.claims, topic);
        claim.is_active = false;
        identity.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut identity.claim_revoked_events, ClaimRevokedEvent {
            identity: identity.owner,
            topic,
            revoked_by,
            revoked_at: current_time,
        });
    }
    
    /// Update claim data
    public fun update_claim(
        account: &signer,
        topic: u256,
        new_data: vector<u8>,
        new_uri: String
    ) acquires Identity {
        let identity = borrow_global_mut<Identity>(signer::address_of(account));
        let current_time = timestamp::now_seconds();
        
        // Check if identity is frozen
        assert!(!identity.is_frozen, constants::get_identity_frozen_error());
        
        // Check if claim exists
        assert!(table::contains(&identity.claims, topic), constants::get_identity_claim_not_found_error());
        
        let claim = table::borrow_mut(&mut identity.claims, topic);
        assert!(claim.is_active, constants::get_identity_claim_invalid_error());
        
        // Check if claim is not expired
        if (claim.expiration_date > 0) {
            assert!(claim.expiration_date > current_time, constants::get_identity_claim_expired_error());
        };
        
        claim.data = new_data;
        claim.uri = new_uri;
        identity.updated_at = current_time;
    }

    // ========== METADATA MANAGEMENT ==========
    
    /// Update identity metadata
    public fun update_metadata(
        account: &signer,
        kyc_level: u8,
        investor_type: u8,
        age_verified: bool,
        pep_status: bool,
        sanctions_checked: bool,
        country_code: vector<u8>
    ) acquires Identity {
        let identity = borrow_global_mut<Identity>(signer::address_of(account));
        let current_time = timestamp::now_seconds();
        
        // Check if identity is frozen
        assert!(!identity.is_frozen, constants::get_identity_frozen_error());
        
        // Validate parameters
        assert!(constants::is_valid_kyc_level(kyc_level), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_investor_type(investor_type), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_country_code(country_code), constants::get_invalid_parameter_error());
        
        identity.metadata.kyc_level = kyc_level;
        identity.metadata.investor_type = investor_type;
        identity.metadata.age_verified = age_verified;
        identity.metadata.pep_status = pep_status;
        identity.metadata.sanctions_checked = sanctions_checked;
        identity.metadata.country_code = country_code;
        identity.metadata.last_updated = current_time;
        identity.updated_at = current_time;
    }
    
    /// Update KYC level
    public fun update_kyc_level(
        account: &signer,
        kyc_level: u8
    ) acquires Identity {
        let identity = borrow_global_mut<Identity>(signer::address_of(account));
        let current_time = timestamp::now_seconds();
        
        // Check if identity is frozen
        assert!(!identity.is_frozen, constants::get_identity_frozen_error());
        
        // Validate KYC level
        assert!(constants::is_valid_kyc_level(kyc_level), constants::get_invalid_parameter_error());
        
        identity.metadata.kyc_level = kyc_level;
        identity.metadata.last_updated = current_time;
        identity.updated_at = current_time;
    }
    
    /// Update investor type
    public fun update_investor_type(
        account: &signer,
        investor_type: u8
    ) acquires Identity {
        let identity = borrow_global_mut<Identity>(signer::address_of(account));
        let current_time = timestamp::now_seconds();
        
        // Check if identity is frozen
        assert!(!identity.is_frozen, constants::get_identity_frozen_error());
        
        // Validate investor type
        assert!(constants::is_valid_investor_type(investor_type), constants::get_invalid_parameter_error());
        
        identity.metadata.investor_type = investor_type;
        identity.metadata.last_updated = current_time;
        identity.updated_at = current_time;
    }

    // ========== RECOVERY MANAGEMENT ==========
    
    /// Set up identity recovery
    public fun setup_recovery(
        account: &signer,
        recovery_addresses: vector<address>,
        recovery_threshold: u64,
        recovery_delay: u64
    ) acquires Identity {
        let identity = borrow_global_mut<Identity>(signer::address_of(account));
        let current_time = timestamp::now_seconds();
        
        // Check if identity is frozen
        assert!(!identity.is_frozen, constants::get_identity_frozen_error());
        
        // Validate parameters
        assert!(vector::length(&recovery_addresses) > 0, constants::get_invalid_parameter_error());
        assert!(recovery_threshold > 0 && recovery_threshold <= vector::length(&recovery_addresses), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_duration(recovery_delay), constants::get_invalid_parameter_error());
        
        identity.recovery.recovery_addresses = recovery_addresses;
        identity.recovery.recovery_threshold = recovery_threshold;
        identity.recovery.recovery_delay = recovery_delay;
        identity.recovery.is_active = true;
        identity.updated_at = current_time;
    }
    
    /// Execute identity recovery
    public fun execute_recovery(
        account: &signer,
        new_owner: address,
        recovery_signatures: vector<vector<u8>>
    ) acquires Identity {
        let identity = borrow_global_mut<Identity>(signer::address_of(account));
        let current_time = timestamp::now_seconds();
        
        // Check if recovery is active
        assert!(identity.recovery.is_active, constants::get_identity_recovery_not_authorized_error());
        
        // Check if enough signatures provided
        assert!(vector::length(&recovery_signatures) >= identity.recovery.recovery_threshold, constants::get_identity_recovery_not_authorized_error());
        
        // TODO: Verify recovery signatures
        
        let old_owner = identity.owner;
        identity.owner = new_owner;
        identity.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut identity.identity_recovered_events, IdentityRecoveredEvent {
            identity: new_owner,
            old_owner,
            new_owner,
            recovered_at: current_time,
        });
    }

    // ========== FREEZE/UNFREEZE ==========
    
    /// Freeze identity
    public fun freeze_identity(
        account: &signer,
        freeze_reason: String
    ) acquires Identity {
        let identity = borrow_global_mut<Identity>(signer::address_of(account));
        let current_time = timestamp::now_seconds();
        
        // Check if identity is already frozen
        assert!(!identity.is_frozen, constants::get_identity_frozen_error());
        
        identity.is_frozen = true;
        identity.freeze_reason = freeze_reason;
        identity.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut identity.identity_frozen_events, IdentityFrozenEvent {
            identity: identity.owner,
            frozen_by: identity.owner, // This should be updated to actual freezer
            frozen_at: current_time,
            freeze_reason,
        });
    }
    
    /// Unfreeze identity
    public fun unfreeze_identity(
        account: &signer
    ) acquires Identity {
        let identity = borrow_global_mut<Identity>(signer::address_of(account));
        let current_time = timestamp::now_seconds();
        
        // Check if identity is frozen
        assert!(identity.is_frozen, constants::get_identity_frozen_error());
        
        identity.is_frozen = false;
        identity.freeze_reason = string::utf8(b"");
        identity.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut identity.identity_unfrozen_events, IdentityUnfrozenEvent {
            identity: identity.owner,
            unfrozen_by: identity.owner, // This should be updated to actual unfreezer
            unfrozen_at: current_time,
        });
    }

    // ========== VIEW FUNCTIONS ==========
    
    /// Get identity owner
    public fun get_identity_owner(user: address): address acquires Identity {
        let identity = borrow_global<Identity>(user);
        identity.owner
    }
    
    /// Check if identity is frozen
    public fun is_identity_frozen(user: address): bool acquires Identity {
        let identity = borrow_global<Identity>(user);
        identity.is_frozen
    }
    
    /// Get identity metadata
    public fun get_identity_metadata(user: address): (u8, u8, bool, bool, bool, vector<u8>, u64, u64) acquires Identity {
        let identity = borrow_global<Identity>(user);
        (
            identity.metadata.kyc_level,
            identity.metadata.investor_type,
            identity.metadata.age_verified,
            identity.metadata.pep_status,
            identity.metadata.sanctions_checked,
            identity.metadata.country_code,
            identity.metadata.date_of_birth,
            identity.metadata.last_updated,
        )
    }
    
    /// Get claim information
    public fun get_claim(user: address, topic: u256): (u8, address, vector<u8>, vector<u8>, String, u64, u64, bool) acquires Identity {
        let identity = borrow_global<Identity>(user);
        assert!(table::contains(&identity.claims, topic), constants::get_identity_claim_not_found_error());
        
        let claim = table::borrow(&identity.claims, topic);
        (
            claim.scheme,
            claim.issuer,
            claim.signature,
            claim.data,
            claim.uri,
            claim.issuance_date,
            claim.expiration_date,
            claim.is_active,
        )
    }
    
    /// Check if claim exists and is valid
    public fun is_claim_valid(user: address, topic: u256): bool acquires Identity {
        let identity = borrow_global<Identity>(user);
        
        if (!table::contains(&identity.claims, topic)) {
            return false
        };
        
        let claim = table::borrow(&identity.claims, topic);
        if (!claim.is_active) {
            return false
        };
        
        // Check if claim is expired
        if (claim.expiration_date > 0) {
            let current_time = timestamp::now_seconds();
            if (claim.expiration_date <= current_time) {
                return false
            };
        };
        
        true
    }
    
    /// Get all claim topics
    public fun get_claim_topics(user: address): vector<u256> acquires Identity {
        let identity = borrow_global<Identity>(user);
        let topics = vector::empty();
        
        // Note: This is a simplified implementation
        // In a real implementation, you would iterate through the table
        topics
    }
    
    /// Get recovery information
    public fun get_recovery_info(user: address): (vector<address>, u64, u64, bool) acquires Identity {
        let identity = borrow_global<Identity>(user);
        (
            identity.recovery.recovery_addresses,
            identity.recovery.recovery_threshold,
            identity.recovery.recovery_delay,
            identity.recovery.is_active,
        )
    }
    
    /// Get identity creation and update timestamps
    public fun get_identity_timestamps(user: address): (u64, u64) acquires Identity {
        let identity = borrow_global<Identity>(user);
        (identity.created_at, identity.updated_at)
    }
    
    /// Get freeze information
    public fun get_freeze_info(user: address): (bool, String) acquires Identity {
        let identity = borrow_global<Identity>(user);
        (identity.is_frozen, identity.freeze_reason)
    }
    
    /// Delete an identity (can only be called by authorized modules)
    /// Note: This function is currently not implemented to avoid resource destruction issues
    /// Identities should be frozen instead of deleted
    public(friend) fun delete_identity_internal(_user: address) {
        // Instead of deleting the identity resource, we'll just abort
        // Identities should be frozen instead of deleted to avoid issues with dropping tables
        abort constants::get_identity_not_found_error()
    }
}
