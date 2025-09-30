/// Settlement module for T-REX compliant token system
/// Implements settlement functionality for DVP and DVE orders

module FARE::settlement {
    use std::vector;
    use std::string::{Self, String};
    use std::table::{Self, Table};
    use std::error;
    use std::signer;
    use std::timestamp;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata};
    use aptos_framework::primary_fungible_store;
    use FARE::constants;
    use FARE::trex_token;
    use FARE::onchain_identity;

    // ========== STRUCTS ==========
    
    /// Settlement request information
    struct SettlementRequest has store, copy, drop {
        /// Request ID
        request_id: u64,
        /// Settlement type (DVP or DVE)
        settlement_type: u8,
        /// Order ID
        order_id: u64,
        /// Seller address
        seller: address,
        /// Buyer address
        buyer: address,
        /// Token address
        token_address: address,
        /// Token amount
        token_amount: u64,
        /// Payment amount
        payment_amount: u64,
        /// Payment token address
        payment_token_address: address,
        /// Settlement status
        status: u8,
        /// Settlement delay
        settlement_delay: u64,
        /// Created timestamp
        created_at: u64,
        /// Settlement timestamp
        settled_at: u64,
    }
    
    /// Settlement batch information
    struct SettlementBatch has store, copy, drop {
        /// Batch ID
        batch_id: u64,
        /// Batch name
        batch_name: String,
        /// Settlement requests in batch
        settlement_requests: vector<u64>,
        /// Batch status
        status: u8,
        /// Batch created timestamp
        created_at: u64,
        /// Batch executed timestamp
        executed_at: u64,
    }
    
    /// Settlement configuration
    struct SettlementConfig has store, copy, drop {
        /// Default settlement delay
        default_settlement_delay: u64,
        /// Batch settlement enabled
        batch_settlement_enabled: bool,
        /// Maximum batch size
        max_batch_size: u64,
        /// Settlement window (seconds)
        settlement_window: u64,
        /// Last settlement window
        last_settlement_window: u64,
        /// Created timestamp
        created_at: u64,
        /// Last updated timestamp
        updated_at: u64,
    }
    
    /// Settlement registry
    struct SettlementRegistry has key {
        /// Map of request ID to settlement request
        settlement_requests: Table<u64, SettlementRequest>,
        /// Map of batch ID to settlement batch
        settlement_batches: Table<u64, SettlementBatch>,
        /// Map of user to their settlement requests
        user_settlements: Table<address, vector<u64>>,
        /// Settlement configuration
        config: SettlementConfig,
        /// Next request ID
        next_request_id: u64,
        /// Next batch ID
        next_batch_id: u64,
        /// Events
        settlement_requested_events: EventHandle<SettlementRequestedEvent>,
        settlement_completed_events: EventHandle<SettlementCompletedEvent>,
        settlement_failed_events: EventHandle<SettlementFailedEvent>,
        batch_created_events: EventHandle<BatchCreatedEvent>,
        batch_executed_events: EventHandle<BatchExecutedEvent>,
    }
    
    /// Settlement requested event
    struct SettlementRequestedEvent has store, drop {
        request_id: u64,
        settlement_type: u8,
        order_id: u64,
        seller: address,
        buyer: address,
        token_address: address,
        token_amount: u64,
        payment_amount: u64,
        payment_token_address: address,
        settlement_delay: u64,
        requested_at: u64,
    }
    
    /// Settlement completed event
    struct SettlementCompletedEvent has store, drop {
        request_id: u64,
        settlement_type: u8,
        order_id: u64,
        seller: address,
        buyer: address,
        token_address: address,
        token_amount: u64,
        payment_amount: u64,
        payment_token_address: address,
        settled_at: u64,
    }
    
    /// Settlement failed event
    struct SettlementFailedEvent has store, drop {
        request_id: u64,
        settlement_type: u8,
        order_id: u64,
        seller: address,
        buyer: address,
        token_address: address,
        token_amount: u64,
        payment_amount: u64,
        payment_token_address: address,
        failed_at: u64,
        failure_reason: String,
    }
    
    /// Batch created event
    struct BatchCreatedEvent has store, drop {
        batch_id: u64,
        batch_name: String,
        request_count: u64,
        created_at: u64,
    }
    
    /// Batch executed event
    struct BatchExecutedEvent has store, drop {
        batch_id: u64,
        batch_name: String,
        executed_count: u64,
        failed_count: u64,
        executed_at: u64,
    }

    // ========== INITIALIZATION ==========
    
    /// Initialize settlement registry
    public fun initialize(account: &signer) {
        let account_addr = signer::address_of(account);
        
        // Ensure account is not already initialized
        assert!(!exists<SettlementRegistry>(account_addr), constants::get_access_control_not_authorized_error());
        
        let current_time = timestamp::now_seconds();
        
        let registry = SettlementRegistry {
            settlement_requests: table::new(),
            settlement_batches: table::new(),
            user_settlements: table::new(),
            config: SettlementConfig {
                default_settlement_delay: 3600, // 1 hour
                batch_settlement_enabled: true,
                max_batch_size: 100,
                settlement_window: 86400, // 24 hours
                last_settlement_window: current_time,
                created_at: current_time,
                updated_at: current_time,
            },
            next_request_id: 1,
            next_batch_id: 1,
            settlement_requested_events: account::new_event_handle<SettlementRequestedEvent>(account),
            settlement_completed_events: account::new_event_handle<SettlementCompletedEvent>(account),
            settlement_failed_events: account::new_event_handle<SettlementFailedEvent>(account),
            batch_created_events: account::new_event_handle<BatchCreatedEvent>(account),
            batch_executed_events: account::new_event_handle<BatchExecutedEvent>(account),
        };
        
        move_to(account, registry);
    }

    // ========== SETTLEMENT REQUEST MANAGEMENT ==========
    
    /// Request settlement
    public fun request_settlement(
        account: &signer,
        settlement_type: u8,
        order_id: u64,
        seller: address,
        buyer: address,
        token_address: address,
        token_amount: u64,
        payment_amount: u64,
        payment_token_address: address,
        settlement_delay: u64
    ): u64 acquires SettlementRegistry {
        let requester = signer::address_of(account);
        let registry = borrow_global_mut<SettlementRegistry>(requester);
        let current_time = timestamp::now_seconds();
        
        // Validate parameters
        assert!(constants::is_valid_amount(token_amount), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_amount(payment_amount), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_duration(settlement_delay), constants::get_invalid_parameter_error());
        
        // Check if token is T-REX compliant
        assert!(trex_token::is_trex_compliant(token_address), constants::get_compliance_check_failed_error());
        
        // Check if payment token is T-REX compliant
        assert!(trex_token::is_trex_compliant(payment_token_address), constants::get_compliance_check_failed_error());
        
        // Check if seller has identity if required
        if (onchain_identity::has_identity(seller)) {
            let (_, kyc_level, investor_type, _, _, _, _) = onchain_identity::get_identity_status(seller);
            // Additional identity checks can be added here
        };
        
        // Check if buyer has identity if required
        if (onchain_identity::has_identity(buyer)) {
            let (_, kyc_level, investor_type, _, _, _, _) = onchain_identity::get_identity_status(buyer);
            // Additional identity checks can be added here
        };
        
        let request_id = registry.next_request_id;
        registry.next_request_id = registry.next_request_id + 1;
        
        let request = SettlementRequest {
            request_id,
            settlement_type,
            order_id,
            seller,
            buyer,
            token_address,
            token_amount,
            payment_amount,
            payment_token_address,
            status: 1, // Pending
            settlement_delay,
            created_at: current_time,
            settled_at: 0,
        };
        
        table::add(&mut registry.settlement_requests, request_id, request);
        
        // Add to user settlements
        if (!table::contains(&registry.user_settlements, seller)) {
            table::add(&mut registry.user_settlements, seller, vector::empty());
        };
        let seller_settlements = table::borrow_mut(&mut registry.user_settlements, seller);
        vector::push_back(seller_settlements, request_id);
        
        if (!table::contains(&registry.user_settlements, buyer)) {
            table::add(&mut registry.user_settlements, buyer, vector::empty());
        };
        let buyer_settlements = table::borrow_mut(&mut registry.user_settlements, buyer);
        vector::push_back(buyer_settlements, request_id);
        
        // Emit event
        event::emit_event(&mut registry.settlement_requested_events, SettlementRequestedEvent {
            request_id,
            settlement_type,
            order_id,
            seller,
            buyer,
            token_address,
            token_amount,
            payment_amount,
            payment_token_address,
            settlement_delay,
            requested_at: current_time,
        });
        
        request_id
    }
    
    /// Execute settlement
    public fun execute_settlement(
        account: &signer,
        request_id: u64
    ) acquires SettlementRegistry {
        let executor = signer::address_of(account);
        let registry = borrow_global_mut<SettlementRegistry>(executor);
        let current_time = timestamp::now_seconds();
        
        // Check if settlement request exists
        assert!(table::contains(&registry.settlement_requests, request_id), constants::get_dvp_settlement_failed_error());
        
        let request = table::borrow_mut(&mut registry.settlement_requests, request_id);
        
        // Check if settlement is still pending
        assert!(request.status == 1, constants::get_dvp_settlement_failed_error());
        
        // Check if settlement delay has passed
        assert!(current_time >= request.created_at + request.settlement_delay, constants::get_dvp_settlement_failed_error());
        
        // Perform the actual settlement
        let settlement_success = perform_settlement_transfer(
            request.seller,
            request.buyer,
            request.token_address,
            request.token_amount,
            request.payment_token_address,
            request.payment_amount
        );
        
        if (settlement_success) {
            // Update settlement status
            request.status = 2; // Completed
            request.settled_at = current_time;
            
            // Emit event
            event::emit_event(&mut registry.settlement_completed_events, SettlementCompletedEvent {
                request_id,
                settlement_type: request.settlement_type,
                order_id: request.order_id,
                seller: request.seller,
                buyer: request.buyer,
                token_address: request.token_address,
                token_amount: request.token_amount,
                payment_amount: request.payment_amount,
                payment_token_address: request.payment_token_address,
                settled_at: current_time,
            });
        } else {
            // Update settlement status
            request.status = 3; // Failed
            request.settled_at = current_time;
            
            // Emit event
            event::emit_event(&mut registry.settlement_failed_events, SettlementFailedEvent {
                request_id,
                settlement_type: request.settlement_type,
                order_id: request.order_id,
                seller: request.seller,
                buyer: request.buyer,
                token_address: request.token_address,
                token_amount: request.token_amount,
                payment_amount: request.payment_amount,
                payment_token_address: request.payment_token_address,
                failed_at: current_time,
                failure_reason: string::utf8(b"Settlement transfer failed"),
            });
        };
    }
    
    /// Perform settlement transfer (internal function)
    fun perform_settlement_transfer(
        seller: address,
        buyer: address,
        token_address: address,
        token_amount: u64,
        payment_token_address: address,
        payment_amount: u64
    ): bool {
        // This is a simplified implementation
        // In a real implementation, you would perform the actual token transfers
        // using the primary_fungible_store::transfer function
        
        // For now, we'll assume the transfer is successful
        true
    }

    // ========== BATCH SETTLEMENT MANAGEMENT ==========
    
    /// Create settlement batch
    public fun create_settlement_batch(
        account: &signer,
        batch_name: String,
        settlement_requests: vector<u64>
    ): u64 acquires SettlementRegistry {
        let creator = signer::address_of(account);
        let registry = borrow_global_mut<SettlementRegistry>(creator);
        let current_time = timestamp::now_seconds();
        
        // Validate parameters
        assert!(vector::length(&settlement_requests) > 0, constants::get_invalid_parameter_error());
        assert!(vector::length(&settlement_requests) <= registry.config.max_batch_size, constants::get_invalid_parameter_error());
        
        let batch_id = registry.next_batch_id;
        registry.next_batch_id = registry.next_batch_id + 1;
        
        let batch = SettlementBatch {
            batch_id,
            batch_name,
            settlement_requests,
            status: 1, // Pending
            created_at: current_time,
            executed_at: 0,
        };
        
        table::add(&mut registry.settlement_batches, batch_id, batch);
        
        // Emit event
        event::emit_event(&mut registry.batch_created_events, BatchCreatedEvent {
            batch_id,
            batch_name,
            request_count: vector::length(&settlement_requests),
            created_at: current_time,
        });
        
        batch_id
    }
    
    /// Execute settlement batch
    public fun execute_settlement_batch(
        account: &signer,
        batch_id: u64
    ) acquires SettlementRegistry {
        let executor = signer::address_of(account);
        let registry = borrow_global_mut<SettlementRegistry>(executor);
        let current_time = timestamp::now_seconds();
        
        // Check if batch exists
        assert!(table::contains(&registry.settlement_batches, batch_id), constants::get_dvp_settlement_failed_error());
        
        let batch = table::borrow_mut(&mut registry.settlement_batches, batch_id);
        
        // Check if batch is still pending
        assert!(batch.status == 1, constants::get_dvp_settlement_failed_error());
        
        // Copy batch name before iterating
        let batch_name = batch.batch_name;
        
        // Execute each settlement in the batch
        let executed_count = 0;
        let failed_count = 0;
        let len = vector::length(&batch.settlement_requests);
        let i = 0;
        while (i < len) {
            let request_id = *vector::borrow(&batch.settlement_requests, i);
            
            if (table::contains(&registry.settlement_requests, request_id)) {
                let request = table::borrow(&registry.settlement_requests, request_id);
                if (request.status == 1 && current_time >= request.created_at + request.settlement_delay) {
                    // Copy values from request to avoid borrow checker issues
                    let seller = request.seller;
                    let buyer = request.buyer;
                    let token_address = request.token_address;
                    let token_amount = request.token_amount;
                    let payment_token_address = request.payment_token_address;
                    let payment_amount = request.payment_amount;
                    
                    // Execute settlement
                    let settlement_success = perform_settlement_transfer(
                        seller,
                        buyer,
                        token_address,
                        token_amount,
                        payment_token_address,
                        payment_amount
                    );
                    
                    if (settlement_success) {
                        executed_count = executed_count + 1;
                    } else {
                        failed_count = failed_count + 1;
                    };
                };
            };
            i = i + 1;
        };
        
        // Update batch status
        let batch_mut = table::borrow_mut(&mut registry.settlement_batches, batch_id);
        batch_mut.status = 2; // Executed
        batch_mut.executed_at = current_time;
        
        // Emit event
        event::emit_event(&mut registry.batch_executed_events, BatchExecutedEvent {
            batch_id,
            batch_name,
            executed_count,
            failed_count,
            executed_at: current_time,
        });
    }

    // ========== CONFIGURATION MANAGEMENT ==========
    
    /// Update settlement configuration
    public fun update_settlement_config(
        account: &signer,
        default_settlement_delay: u64,
        batch_settlement_enabled: bool,
        max_batch_size: u64,
        settlement_window: u64
    ) acquires SettlementRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<SettlementRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Validate parameters
        assert!(constants::is_valid_duration(default_settlement_delay), constants::get_invalid_parameter_error());
        assert!(max_batch_size > 0, constants::get_invalid_parameter_error());
        assert!(constants::is_valid_duration(settlement_window), constants::get_invalid_parameter_error());
        
        registry.config.default_settlement_delay = default_settlement_delay;
        registry.config.batch_settlement_enabled = batch_settlement_enabled;
        registry.config.max_batch_size = max_batch_size;
        registry.config.settlement_window = settlement_window;
        registry.config.updated_at = current_time;
    }

    // ========== VIEW FUNCTIONS ==========
    
    /// Get settlement request information
    public fun get_settlement_request(request_id: u64): (u8, u64, address, address, address, u64, u64, address, u8, u64, u64, u64) acquires SettlementRegistry {
        let registry = borrow_global<SettlementRegistry>(@0x0); // This will need to be updated with actual address
        assert!(table::contains(&registry.settlement_requests, request_id), constants::get_dvp_settlement_failed_error());
        
        let request = table::borrow(&registry.settlement_requests, request_id);
        (
            request.settlement_type,
            request.order_id,
            request.seller,
            request.buyer,
            request.token_address,
            request.token_amount,
            request.payment_amount,
            request.payment_token_address,
            request.status,
            request.settlement_delay,
            request.created_at,
            request.settled_at,
        )
    }
    
    /// Get settlement batch information
    public fun get_settlement_batch(batch_id: u64): (String, vector<u64>, u8, u64, u64) acquires SettlementRegistry {
        let registry = borrow_global<SettlementRegistry>(@0x0); // This will need to be updated with actual address
        assert!(table::contains(&registry.settlement_batches, batch_id), constants::get_dvp_settlement_failed_error());
        
        let batch = table::borrow(&registry.settlement_batches, batch_id);
        (
            batch.batch_name,
            batch.settlement_requests,
            batch.status,
            batch.created_at,
            batch.executed_at,
        )
    }
    
    /// Get settlement configuration
    public fun get_settlement_config(): (u64, bool, u64, u64, u64, u64, u64) acquires SettlementRegistry {
        let registry = borrow_global<SettlementRegistry>(@0x0); // This will need to be updated with actual address
        let config = registry.config;
        (
            config.default_settlement_delay,
            config.batch_settlement_enabled,
            config.max_batch_size,
            config.settlement_window,
            config.last_settlement_window,
            config.created_at,
            config.updated_at,
        )
    }
    
    /// Get user's settlement requests
    public fun get_user_settlements(user: address): vector<u64> acquires SettlementRegistry {
        let registry = borrow_global<SettlementRegistry>(user);
        
        if (!table::contains(&registry.user_settlements, user)) {
            return vector::empty()
        };
        
        *table::borrow(&registry.user_settlements, user)
    }
    
    /// Check if settlement request exists
    public fun does_settlement_request_exist(request_id: u64): bool acquires SettlementRegistry {
        let registry = borrow_global<SettlementRegistry>(@0x0); // This will need to be updated with actual address
        table::contains(&registry.settlement_requests, request_id)
    }
    
    /// Check if settlement request is ready for execution
    public fun is_settlement_ready_for_execution(request_id: u64): bool acquires SettlementRegistry {
        let registry = borrow_global<SettlementRegistry>(@0x0); // This will need to be updated with actual address
        assert!(table::contains(&registry.settlement_requests, request_id), constants::get_dvp_settlement_failed_error());
        
        let request = table::borrow(&registry.settlement_requests, request_id);
        let current_time = timestamp::now_seconds();
        
        request.status == 1 && current_time >= request.created_at + request.settlement_delay
    }
    
    /// Get next request ID
    public fun get_next_request_id(): u64 acquires SettlementRegistry {
        let registry = borrow_global<SettlementRegistry>(@0x0); // This will need to be updated with actual address
        registry.next_request_id
    }
    
    /// Get next batch ID
    public fun get_next_batch_id(): u64 acquires SettlementRegistry {
        let registry = borrow_global<SettlementRegistry>(@0x0); // This will need to be updated with actual address
        registry.next_batch_id
    }
    
    /// Get total number of settlement requests
    public fun get_total_settlement_requests(): u64 acquires SettlementRegistry {
        let registry = borrow_global<SettlementRegistry>(@0x0); // This will need to be updated with actual address
        registry.next_request_id - 1
    }
    
    /// Get total number of settlement batches
    public fun get_total_settlement_batches(): u64 acquires SettlementRegistry {
        let registry = borrow_global<SettlementRegistry>(@0x0); // This will need to be updated with actual address
        registry.next_batch_id - 1
    }
}
