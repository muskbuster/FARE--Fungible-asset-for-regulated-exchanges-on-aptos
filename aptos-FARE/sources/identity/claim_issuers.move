/// Claim Issuers module for T-REX compliant token system
/// Manages trusted claim issuers and their permissions

module FARE::claim_issuers {
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
    
    /// Claim issuer information
    struct ClaimIssuer has store, copy, drop {
        /// Issuer name
        name: String,
        /// Issuer URL
        url: String,
        /// Whether issuer is active
        is_active: bool,
        /// Number of claims issued
        claim_count: u64,
        /// Allowed claim topics
        allowed_topics: vector<u256>,
        /// Issuer reputation score
        reputation_score: u8,
        /// Created timestamp
        created_at: u64,
        /// Last updated timestamp
        updated_at: u64,
    }
    
    /// Claim issuer permissions
    struct ClaimIssuerPermissions has store, copy, drop {
        /// Issuer address
        issuer: address,
        /// Allowed claim topics
        allowed_topics: vector<u256>,
        /// Maximum claims per day
        daily_claim_limit: u64,
        /// Current daily claim count
        daily_claim_count: u64,
        /// Last reset date
        last_reset_date: u64,
        /// Whether issuer can issue batch claims
        can_issue_batch: bool,
        /// Whether issuer can revoke claims
        can_revoke_claims: bool,
    }
    
    /// Batch claim issuance request
    struct BatchClaimRequest has store, copy, drop {
        /// Request ID
        request_id: u64,
        /// Issuer address
        issuer: address,
        /// Target identities
        target_identities: vector<address>,
        /// Claim topics
        claim_topics: vector<u256>,
        /// Claim data
        claim_data: vector<vector<u8>>,
        /// Request status
        status: u8,
        /// Created timestamp
        created_at: u64,
        /// Expiration timestamp
        expires_at: u64,
    }
    
    /// Claim issuers registry
    struct ClaimIssuersRegistry has key {
        /// Map of issuer address to issuer info
        issuers: Table<address, ClaimIssuer>,
        /// Map of issuer address to permissions
        issuer_permissions: Table<address, ClaimIssuerPermissions>,
        /// Pending batch claim requests
        batch_requests: Table<u64, BatchClaimRequest>,
        /// Next batch request ID
        next_batch_request_id: u64,
        /// Events
        issuer_registered_events: EventHandle<IssuerRegisteredEvent>,
        issuer_updated_events: EventHandle<IssuerUpdatedEvent>,
        issuer_deactivated_events: EventHandle<IssuerDeactivatedEvent>,
        batch_claim_requested_events: EventHandle<BatchClaimRequestedEvent>,
        batch_claim_executed_events: EventHandle<BatchClaimExecutedEvent>,
    }
    
    /// Issuer registered event
    struct IssuerRegisteredEvent has store, drop {
        issuer: address,
        name: String,
        url: String,
        allowed_topics: vector<u256>,
        registered_at: u64,
    }
    
    /// Issuer updated event
    struct IssuerUpdatedEvent has store, drop {
        issuer: address,
        updated_by: address,
        updated_at: u64,
    }
    
    /// Issuer deactivated event
    struct IssuerDeactivatedEvent has store, drop {
        issuer: address,
        deactivated_by: address,
        deactivated_at: u64,
    }
    
    /// Batch claim requested event
    struct BatchClaimRequestedEvent has store, drop {
        request_id: u64,
        issuer: address,
        target_count: u64,
        claim_topics: vector<u256>,
        requested_at: u64,
    }
    
    /// Batch claim executed event
    struct BatchClaimExecutedEvent has store, drop {
        request_id: u64,
        issuer: address,
        executed_count: u64,
        executed_at: u64,
    }

    // ========== INITIALIZATION ==========
    
    /// Initialize claim issuers registry
    public fun initialize(account: &signer) {
        let account_addr = signer::address_of(account);
        
        // Ensure account is not already initialized
        assert!(!exists<ClaimIssuersRegistry>(account_addr), constants::get_access_control_not_authorized_error());
        
        let registry = ClaimIssuersRegistry {
            issuers: table::new(),
            issuer_permissions: table::new(),
            batch_requests: table::new(),
            next_batch_request_id: 1,
            issuer_registered_events: account::new_event_handle<IssuerRegisteredEvent>(account),
            issuer_updated_events: account::new_event_handle<IssuerUpdatedEvent>(account),
            issuer_deactivated_events: account::new_event_handle<IssuerDeactivatedEvent>(account),
            batch_claim_requested_events: account::new_event_handle<BatchClaimRequestedEvent>(account),
            batch_claim_executed_events: account::new_event_handle<BatchClaimExecutedEvent>(account),
        };
        
        move_to(account, registry);
    }

    // ========== ISSUER MANAGEMENT ==========
    
    /// Register a new claim issuer
    public fun register_issuer(
        account: &signer,
        issuer: address,
        name: String,
        url: String,
        allowed_topics: vector<u256>,
        daily_claim_limit: u64,
        can_issue_batch: bool,
        can_revoke_claims: bool
    ) acquires ClaimIssuersRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<ClaimIssuersRegistry>(@0x0);
        let current_time = timestamp::now_seconds();
        
        // Check if issuer is already registered
        assert!(!table::contains(&registry.issuers, issuer), constants::get_access_control_not_authorized_error());
        
        // Validate parameters
        assert!(vector::length(&allowed_topics) > 0, constants::get_invalid_parameter_error());
        assert!(daily_claim_limit > 0, constants::get_invalid_parameter_error());
        
        let issuer_info = ClaimIssuer {
            name,
            url,
            is_active: true,
            claim_count: 0,
            allowed_topics,
            reputation_score: 100, // Start with perfect reputation
            created_at: current_time,
            updated_at: current_time,
        };
        
        let permissions = ClaimIssuerPermissions {
            issuer,
            allowed_topics,
            daily_claim_limit,
            daily_claim_count: 0,
            last_reset_date: current_time,
            can_issue_batch,
            can_revoke_claims,
        };
        
        table::add(&mut registry.issuers, issuer, issuer_info);
        table::add(&mut registry.issuer_permissions, issuer, permissions);
        
        // Emit event
        event::emit_event(&mut registry.issuer_registered_events, IssuerRegisteredEvent {
            issuer,
            name,
            url,
            allowed_topics,
            registered_at: current_time,
        });
    }
    
    /// Update issuer information
    public fun update_issuer(
        account: &signer,
        issuer: address,
        name: String,
        url: String,
        allowed_topics: vector<u256>
    ) acquires ClaimIssuersRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<ClaimIssuersRegistry>(@0x0);
        let current_time = timestamp::now_seconds();
        
        // Check if issuer exists
        assert!(table::contains(&registry.issuers, issuer), constants::get_access_control_not_authorized_error());
        
        // Validate parameters
        assert!(vector::length(&allowed_topics) > 0, constants::get_invalid_parameter_error());
        
        let issuer_info = table::borrow_mut(&mut registry.issuers, issuer);
        issuer_info.name = name;
        issuer_info.url = url;
        issuer_info.allowed_topics = allowed_topics;
        issuer_info.updated_at = current_time;
        
        let permissions = table::borrow_mut(&mut registry.issuer_permissions, issuer);
        permissions.allowed_topics = allowed_topics;
        
        // Emit event
        event::emit_event(&mut registry.issuer_updated_events, IssuerUpdatedEvent {
            issuer,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }
    
    /// Deactivate an issuer
    public fun deactivate_issuer(
        account: &signer,
        issuer: address
    ) acquires ClaimIssuersRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<ClaimIssuersRegistry>(@0x0);
        let current_time = timestamp::now_seconds();
        
        // Check if issuer exists
        assert!(table::contains(&registry.issuers, issuer), constants::get_access_control_not_authorized_error());
        
        let issuer_info = table::borrow_mut(&mut registry.issuers, issuer);
        issuer_info.is_active = false;
        issuer_info.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut registry.issuer_deactivated_events, IssuerDeactivatedEvent {
            issuer,
            deactivated_by: account_addr,
            deactivated_at: current_time,
        });
    }
    
    /// Reactivate an issuer
    public fun reactivate_issuer(
        account: &signer,
        issuer: address
    ) acquires ClaimIssuersRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<ClaimIssuersRegistry>(@0x0);
        let current_time = timestamp::now_seconds();
        
        // Check if issuer exists
        assert!(table::contains(&registry.issuers, issuer), constants::get_access_control_not_authorized_error());
        
        let issuer_info = table::borrow_mut(&mut registry.issuers, issuer);
        issuer_info.is_active = true;
        issuer_info.updated_at = current_time;
    }

    // ========== PERMISSIONS MANAGEMENT ==========
    
    /// Update issuer permissions
    public fun update_issuer_permissions(
        account: &signer,
        issuer: address,
        daily_claim_limit: u64,
        can_issue_batch: bool,
        can_revoke_claims: bool
    ) acquires ClaimIssuersRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<ClaimIssuersRegistry>(@0x0);
        let current_time = timestamp::now_seconds();
        
        // Check if issuer exists
        assert!(table::contains(&registry.issuer_permissions, issuer), constants::get_access_control_not_authorized_error());
        
        // Validate parameters
        assert!(daily_claim_limit > 0, constants::get_invalid_parameter_error());
        
        let permissions = table::borrow_mut(&mut registry.issuer_permissions, issuer);
        permissions.daily_claim_limit = daily_claim_limit;
        permissions.can_issue_batch = can_issue_batch;
        permissions.can_revoke_claims = can_revoke_claims;
        
        // Emit event
        event::emit_event(&mut registry.issuer_updated_events, IssuerUpdatedEvent {
            issuer,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }
    
    /// Update issuer reputation score
    public fun update_issuer_reputation(
        account: &signer,
        issuer: address,
        reputation_score: u8
    ) acquires ClaimIssuersRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<ClaimIssuersRegistry>(@0x0);
        let current_time = timestamp::now_seconds();
        
        // Check if issuer exists
        assert!(table::contains(&registry.issuers, issuer), constants::get_access_control_not_authorized_error());
        
        // Validate reputation score (0-100)
        assert!(reputation_score <= 100, constants::get_invalid_parameter_error());
        
        let issuer_info = table::borrow_mut(&mut registry.issuers, issuer);
        issuer_info.reputation_score = reputation_score;
        issuer_info.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut registry.issuer_updated_events, IssuerUpdatedEvent {
            issuer,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }

    // ========== BATCH CLAIM MANAGEMENT ==========
    
    /// Request batch claim issuance
    public fun request_batch_claims(
        account: &signer,
        target_identities: vector<address>,
        claim_topics: vector<u256>,
        claim_data: vector<vector<u8>>,
        expires_at: u64
    ): u64 acquires ClaimIssuersRegistry {
        let issuer = signer::address_of(account);
        let registry = borrow_global_mut<ClaimIssuersRegistry>(@0x0);
        let current_time = timestamp::now_seconds();
        
        // Check if issuer exists and is active
        assert!(table::contains(&registry.issuers, issuer), constants::get_access_control_not_authorized_error());
        let issuer_info = table::borrow(&registry.issuers, issuer);
        assert!(issuer_info.is_active, constants::get_access_control_not_authorized_error());
        
        // Check if issuer can issue batch claims
        let permissions = table::borrow(&registry.issuer_permissions, issuer);
        assert!(permissions.can_issue_batch, constants::get_access_control_not_authorized_error());
        
        // Validate parameters
        assert!(vector::length(&target_identities) > 0, constants::get_invalid_parameter_error());
        assert!(vector::length(&claim_topics) > 0, constants::get_invalid_parameter_error());
        assert!(vector::length(&claim_data) > 0, constants::get_invalid_parameter_error());
        assert!(expires_at > current_time, constants::get_invalid_parameter_error());
        
        let request_id = registry.next_batch_request_id;
        registry.next_batch_request_id = registry.next_batch_request_id + 1;
        
        let request = BatchClaimRequest {
            request_id,
            issuer,
            target_identities,
            claim_topics,
            claim_data,
            status: 1, // Pending
            created_at: current_time,
            expires_at,
        };
        
        table::add(&mut registry.batch_requests, request_id, request);
        
        // Emit event
        event::emit_event(&mut registry.batch_claim_requested_events, BatchClaimRequestedEvent {
            request_id,
            issuer,
            target_count: vector::length(&target_identities),
            claim_topics,
            requested_at: current_time,
        });
        
        request_id
    }
    
    /// Execute batch claim issuance
    public fun execute_batch_claims(
        account: &signer,
        request_id: u64
    ) acquires ClaimIssuersRegistry {
        let issuer = signer::address_of(account);
        let registry = borrow_global_mut<ClaimIssuersRegistry>(@0x0);
        let current_time = timestamp::now_seconds();
        
        // Check if request exists
        assert!(table::contains(&registry.batch_requests, request_id), constants::get_access_control_not_authorized_error());
        
        let request = table::borrow_mut(&mut registry.batch_requests, request_id);
        
        // Check if request is valid
        assert!(request.issuer == issuer, constants::get_access_control_not_authorized_error());
        assert!(request.status == 1, constants::get_access_control_not_authorized_error()); // Pending
        assert!(current_time <= request.expires_at, constants::get_access_control_not_authorized_error());
        
        // Update request status
        request.status = 2; // Executed
        
        // Update issuer claim count
        let issuer_info = table::borrow_mut(&mut registry.issuers, issuer);
        issuer_info.claim_count = issuer_info.claim_count + vector::length(&request.target_identities);
        
        // Update daily claim count
        let permissions = table::borrow_mut(&mut registry.issuer_permissions, issuer);
        permissions.daily_claim_count = permissions.daily_claim_count + vector::length(&request.target_identities);
        
        // Emit event
        event::emit_event(&mut registry.batch_claim_executed_events, BatchClaimExecutedEvent {
            request_id,
            issuer,
            executed_count: vector::length(&request.target_identities),
            executed_at: current_time,
        });
    }
    
    /// Cancel batch claim request
    public fun cancel_batch_claims(
        account: &signer,
        request_id: u64
    ) acquires ClaimIssuersRegistry {
        let issuer = signer::address_of(account);
        let registry = borrow_global_mut<ClaimIssuersRegistry>(@0x0);
        
        // Check if request exists
        assert!(table::contains(&registry.batch_requests, request_id), constants::get_access_control_not_authorized_error());
        
        let request = table::borrow_mut(&mut registry.batch_requests, request_id);
        
        // Check if request is valid
        assert!(request.issuer == issuer, constants::get_access_control_not_authorized_error());
        assert!(request.status == 1, constants::get_access_control_not_authorized_error()); // Pending
        
        // Update request status
        request.status = 3; // Cancelled
    }

    // ========== VIEW FUNCTIONS ==========
    
    /// Check if issuer is registered and active
    public fun is_issuer_active(issuer: address): bool acquires ClaimIssuersRegistry {
        let registry = borrow_global<ClaimIssuersRegistry>(issuer);
        
        if (!table::contains(&registry.issuers, issuer)) {
            return false
        };
        
        let issuer_info = table::borrow(&registry.issuers, issuer);
        issuer_info.is_active
    }
    
    /// Get issuer information
    public fun get_issuer_info(issuer: address): (String, String, bool, u64, vector<u256>, u8, u64, u64) acquires ClaimIssuersRegistry {
        let registry = borrow_global<ClaimIssuersRegistry>(issuer);
        assert!(table::contains(&registry.issuers, issuer), constants::get_access_control_not_authorized_error());
        
        let issuer_info = table::borrow(&registry.issuers, issuer);
        (
            issuer_info.name,
            issuer_info.url,
            issuer_info.is_active,
            issuer_info.claim_count,
            issuer_info.allowed_topics,
            issuer_info.reputation_score,
            issuer_info.created_at,
            issuer_info.updated_at,
        )
    }
    
    /// Get issuer permissions
    public fun get_issuer_permissions(issuer: address): (vector<u256>, u64, u64, u64, bool, bool) acquires ClaimIssuersRegistry {
        let registry = borrow_global<ClaimIssuersRegistry>(issuer);
        assert!(table::contains(&registry.issuer_permissions, issuer), constants::get_access_control_not_authorized_error());
        
        let permissions = table::borrow(&registry.issuer_permissions, issuer);
        (
            permissions.allowed_topics,
            permissions.daily_claim_limit,
            permissions.daily_claim_count,
            permissions.last_reset_date,
            permissions.can_issue_batch,
            permissions.can_revoke_claims,
        )
    }
    
    /// Check if issuer can issue claim for topic
    public fun can_issuer_issue_claim(issuer: address, topic: u256): bool acquires ClaimIssuersRegistry {
        let registry = borrow_global<ClaimIssuersRegistry>(issuer);
        
        if (!table::contains(&registry.issuers, issuer)) {
            return false
        };
        
        let issuer_info = table::borrow(&registry.issuers, issuer);
        if (!issuer_info.is_active) {
            return false
        };
        
        let permissions = table::borrow(&registry.issuer_permissions, issuer);
        let (found, _) = find_topic_index(&permissions.allowed_topics, topic);
        found
    }
    
    /// Check if issuer has reached daily claim limit
    public fun has_issuer_reached_daily_limit(issuer: address): bool acquires ClaimIssuersRegistry {
        let registry = borrow_global<ClaimIssuersRegistry>(issuer);
        
        if (!table::contains(&registry.issuer_permissions, issuer)) {
            return true
        };
        
        let permissions = table::borrow(&registry.issuer_permissions, issuer);
        permissions.daily_claim_count >= permissions.daily_claim_limit
    }
    
    /// Get batch claim request information
    public fun get_batch_claim_request(request_id: u64): (address, vector<address>, vector<u256>, vector<vector<u8>>, u8, u64, u64) acquires ClaimIssuersRegistry {
        let registry = borrow_global<ClaimIssuersRegistry>(@0x0); // This will need to be updated with actual address
        assert!(table::contains(&registry.batch_requests, request_id), constants::get_access_control_not_authorized_error());
        
        let request = table::borrow(&registry.batch_requests, request_id);
        (
            request.issuer,
            request.target_identities,
            request.claim_topics,
            request.claim_data,
            request.status,
            request.created_at,
            request.expires_at,
        )
    }
    
    /// Reset daily claim count for issuer
    public fun reset_daily_claim_count(
        account: &signer,
        issuer: address
    ) acquires ClaimIssuersRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<ClaimIssuersRegistry>(@0x0);
        let current_time = timestamp::now_seconds();
        
        // Check if issuer exists
        assert!(table::contains(&registry.issuer_permissions, issuer), constants::get_access_control_not_authorized_error());
        
        let permissions = table::borrow_mut(&mut registry.issuer_permissions, issuer);
        permissions.daily_claim_count = 0;
        permissions.last_reset_date = current_time;
    }

    // ========== HELPER FUNCTIONS ==========
    
    /// Find topic index in allowed topics vector
    fun find_topic_index(allowed_topics: &vector<u256>, topic: u256): (bool, u64) {
        let len = vector::length(allowed_topics);
        let i = 0;
        while (i < len) {
            let allowed_topic = *vector::borrow(allowed_topics, i);
            if (allowed_topic == topic) {
                return (true, i)
            };
            i = i + 1;
        };
        (false, 0)
    }
}
