/// DVP Manager module for T-REX compliant token system
/// Implements Delivery vs Payment (DVP) functionality

module FARE::dvp_manager {
    use std::vector;
    use std::string::{Self, String};
    use std::table::{Self, Table};
    use std::error;
    use std::signer;
    use std::timestamp;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata};
    use aptos_framework::primary_fungible_store;
    use FARE::constants;
    use FARE::trex_token;
    use FARE::onchain_identity;

    // ========== STRUCTS ==========
    
    /// DVP order information
    struct DVPOrder has store, copy, drop {
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
        /// Order status
        status: u8,
        /// Order expiry timestamp
        expiry: u64,
        /// Created timestamp
        created_at: u64,
        /// Last updated timestamp
        updated_at: u64,
    }
    
    /// DVP escrow information
    struct DVPEscrow has store, copy, drop {
        /// Escrow ID
        escrow_id: u64,
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
        /// Escrow status
        status: u8,
        /// Created timestamp
        created_at: u64,
        /// Last updated timestamp
        updated_at: u64,
    }
    
    /// DVP settlement information
    struct DVPSettlement has store, copy, drop {
        /// Settlement ID
        settlement_id: u64,
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
        /// Settlement timestamp
        settled_at: u64,
    }
    
    /// DVP manager registry
    struct DVPManagerRegistry has key {
        /// Map of order ID to DVP order
        dvp_orders: Table<u64, DVPOrder>,
        /// Map of escrow ID to DVP escrow
        dvp_escrows: Table<u64, DVPEscrow>,
        /// Map of settlement ID to DVP settlement
        dvp_settlements: Table<u64, DVPSettlement>,
        /// Map of user to their orders
        user_orders: Table<address, vector<u64>>,
        /// Next order ID
        next_order_id: u64,
        /// Next escrow ID
        next_escrow_id: u64,
        /// Next settlement ID
        next_settlement_id: u64,
        /// Events
        dvp_order_created_events: EventHandle<DVPOrderCreatedEvent>,
        dvp_order_cancelled_events: EventHandle<DVPOrderCancelledEvent>,
        dvp_order_expired_events: EventHandle<DVPOrderExpiredEvent>,
        dvp_escrow_created_events: EventHandle<DVPEscrowCreatedEvent>,
        dvp_settlement_completed_events: EventHandle<DVPSettlementCompletedEvent>,
        dvp_settlement_failed_events: EventHandle<DVPSettlementFailedEvent>,
    }
    
    /// DVP order created event
    struct DVPOrderCreatedEvent has store, drop {
        order_id: u64,
        seller: address,
        buyer: address,
        token_address: address,
        token_amount: u64,
        payment_amount: u64,
        payment_token_address: address,
        expiry: u64,
        created_at: u64,
    }
    
    /// DVP order cancelled event
    struct DVPOrderCancelledEvent has store, drop {
        order_id: u64,
        cancelled_by: address,
        cancelled_at: u64,
    }
    
    /// DVP order expired event
    struct DVPOrderExpiredEvent has store, drop {
        order_id: u64,
        expired_at: u64,
    }
    
    /// DVP escrow created event
    struct DVPEscrowCreatedEvent has store, drop {
        escrow_id: u64,
        order_id: u64,
        seller: address,
        buyer: address,
        token_address: address,
        token_amount: u64,
        payment_amount: u64,
        payment_token_address: address,
        created_at: u64,
    }
    
    /// DVP settlement completed event
    struct DVPSettlementCompletedEvent has store, drop {
        settlement_id: u64,
        order_id: u64,
        seller: address,
        buyer: address,
        token_address: address,
        token_amount: u64,
        payment_amount: u64,
        payment_token_address: address,
        settled_at: u64,
    }
    
    /// DVP settlement failed event
    struct DVPSettlementFailedEvent has store, drop {
        settlement_id: u64,
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

    // ========== INITIALIZATION ==========
    
    /// Initialize DVP manager registry
    public fun initialize(account: &signer) {
        let account_addr = signer::address_of(account);
        
        // Ensure account is not already initialized
        assert!(!exists<DVPManagerRegistry>(account_addr), constants::get_access_control_not_authorized_error());
        
        let registry = DVPManagerRegistry {
            dvp_orders: table::new(),
            dvp_escrows: table::new(),
            dvp_settlements: table::new(),
            user_orders: table::new(),
            next_order_id: 1,
            next_escrow_id: 1,
            next_settlement_id: 1,
            dvp_order_created_events: account::new_event_handle<DVPOrderCreatedEvent>(account),
            dvp_order_cancelled_events: account::new_event_handle<DVPOrderCancelledEvent>(account),
            dvp_order_expired_events: account::new_event_handle<DVPOrderExpiredEvent>(account),
            dvp_escrow_created_events: account::new_event_handle<DVPEscrowCreatedEvent>(account),
            dvp_settlement_completed_events: account::new_event_handle<DVPSettlementCompletedEvent>(account),
            dvp_settlement_failed_events: account::new_event_handle<DVPSettlementFailedEvent>(account),
        };
        
        move_to(account, registry);
    }

    // ========== DVP ORDER MANAGEMENT ==========
    
    /// Create a new DVP order
    public fun create_dvp_order(
        account: &signer,
        buyer: address,
        token_address: address,
        token_amount: u64,
        payment_amount: u64,
        payment_token_address: address,
        expiry: u64
    ): u64 acquires DVPManagerRegistry {
        let seller = signer::address_of(account);
        // Note: This function needs admin address to access registry
        // For now, we'll use a placeholder - this needs to be refactored
        let registry = borrow_global_mut<DVPManagerRegistry>(@0x1);
        let current_time = timestamp::now_seconds();
        
        // Validate parameters
        assert!(constants::is_valid_amount(token_amount), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_amount(payment_amount), constants::get_invalid_parameter_error());
        assert!(expiry > current_time, constants::get_invalid_parameter_error());
        
        // Check if token is T-REX compliant
        assert!(trex_token::is_trex_compliant(token_address), constants::get_compliance_check_failed_error());
        
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
        
        let order_id = registry.next_order_id;
        registry.next_order_id = registry.next_order_id + 1;
        
        let order = DVPOrder {
            order_id,
            seller,
            buyer,
            token_address,
            token_amount,
            payment_amount,
            payment_token_address,
            status: constants::get_dvp_order_status_pending(),
            expiry,
            created_at: current_time,
            updated_at: current_time,
        };
        
        table::add(&mut registry.dvp_orders, order_id, order);
        
        // Add to user orders
        if (!table::contains(&registry.user_orders, seller)) {
            table::add(&mut registry.user_orders, seller, vector::empty());
        };
        let seller_orders = table::borrow_mut(&mut registry.user_orders, seller);
        vector::push_back(seller_orders, order_id);
        
        if (!table::contains(&registry.user_orders, buyer)) {
            table::add(&mut registry.user_orders, buyer, vector::empty());
        };
        let buyer_orders = table::borrow_mut(&mut registry.user_orders, buyer);
        vector::push_back(buyer_orders, order_id);
        
        // Emit event
        event::emit_event(&mut registry.dvp_order_created_events, DVPOrderCreatedEvent {
            order_id,
            seller,
            buyer,
            token_address,
            token_amount,
            payment_amount,
            payment_token_address,
            expiry,
            created_at: current_time,
        });
        
        order_id
    }
    
    /// Cancel a DVP order
    public fun cancel_dvp_order(
        account: &signer,
        order_id: u64
    ) acquires DVPManagerRegistry {
        let canceller = signer::address_of(account);
        // Note: This function needs admin address to access registry
        // For now, we'll use a placeholder - this needs to be refactored
        let registry = borrow_global_mut<DVPManagerRegistry>(@0x1);
        let current_time = timestamp::now_seconds();
        
        // Check if order exists
        assert!(table::contains(&registry.dvp_orders, order_id), constants::get_dvp_order_not_found_error());
        
        let order = table::borrow_mut(&mut registry.dvp_orders, order_id);
        
        // Check if order is still pending
        assert!(order.status == constants::get_dvp_order_status_pending(), constants::get_dvp_order_already_executed_error());
        
        // Check if canceller is seller or buyer
        assert!(order.seller == canceller || order.buyer == canceller, constants::get_access_control_not_authorized_error());
        
        // Update order status
        order.status = constants::get_dvp_order_status_cancelled();
        order.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut registry.dvp_order_cancelled_events, DVPOrderCancelledEvent {
            order_id,
            cancelled_by: canceller,
            cancelled_at: current_time,
        });
    }
    
    /// Execute a DVP order
    public fun execute_dvp_order(
        account: &signer,
        order_id: u64
    ) acquires DVPManagerRegistry {
        let executor = signer::address_of(account);
        // Note: This function needs admin address to access registry
        // For now, we'll use a placeholder - this needs to be refactored
        let registry = borrow_global_mut<DVPManagerRegistry>(@0x1);
        let current_time = timestamp::now_seconds();
        
        // Check if order exists
        assert!(table::contains(&registry.dvp_orders, order_id), constants::get_dvp_order_not_found_error());
        
        let order = table::borrow_mut(&mut registry.dvp_orders, order_id);
        
        // Check if order is still pending
        assert!(order.status == constants::get_dvp_order_status_pending(), constants::get_dvp_order_already_executed_error());
        
        // Check if order has not expired
        assert!(current_time <= order.expiry, constants::get_dvp_order_expired_error());
        
        // Check if executor is buyer
        assert!(order.buyer == executor, constants::get_access_control_not_authorized_error());
        
        // Check if buyer has sufficient payment tokens
        let buyer_payment_balance = trex_token::get_user_balance(order.buyer, order.payment_token_address);
        assert!(buyer_payment_balance >= order.payment_amount, constants::get_insufficient_balance_error());
        
        // Check if seller has sufficient tokens
        let seller_token_balance = trex_token::get_user_balance(order.seller, order.token_address);
        assert!(seller_token_balance >= order.token_amount, constants::get_insufficient_balance_error());
        
        // Perform the actual token transfers
        // For DVP, we use the special DVP transfer function
        // Transfer tokens from seller to buyer
        trex_token::dvp_transfer(order.seller, order.buyer, order.token_address, order.token_amount);
        
        // Transfer payment tokens from buyer to seller
        trex_token::dvp_transfer(order.buyer, order.seller, order.payment_token_address, order.payment_amount);
        
        // Create escrow
        let escrow_id = create_escrow_internal(registry, order_id, current_time);
        
        // Get mutable order to update status
        let order_mut = table::borrow_mut(&mut registry.dvp_orders, order_id);
        order_mut.status = constants::get_dvp_order_status_locked();
        order_mut.updated_at = current_time;
        
        // Perform settlement
        settle_dvp_order_internal(registry, order_id, escrow_id, current_time);
    }
    
    /// Create escrow (internal function)
    fun create_escrow_internal(
        registry: &mut DVPManagerRegistry,
        order_id: u64,
        current_time: u64
    ): u64 {
        let order = table::borrow(&registry.dvp_orders, order_id);
        
        let escrow_id = registry.next_escrow_id;
        registry.next_escrow_id = registry.next_escrow_id + 1;
        
        let escrow = DVPEscrow {
            escrow_id,
            order_id,
            seller: order.seller,
            buyer: order.buyer,
            token_address: order.token_address,
            token_amount: order.token_amount,
            payment_amount: order.payment_amount,
            payment_token_address: order.payment_token_address,
            status: 1, // Active
            created_at: current_time,
            updated_at: current_time,
        };
        
        table::add(&mut registry.dvp_escrows, escrow_id, escrow);
        
        // Emit event
        event::emit_event(&mut registry.dvp_escrow_created_events, DVPEscrowCreatedEvent {
            escrow_id,
            order_id,
            seller: order.seller,
            buyer: order.buyer,
            token_address: order.token_address,
            token_amount: order.token_amount,
            payment_amount: order.payment_amount,
            payment_token_address: order.payment_token_address,
            created_at: current_time,
        });
        
        escrow_id
    }
    
    /// Settle DVP order (internal function)
    fun settle_dvp_order_internal(
        registry: &mut DVPManagerRegistry,
        order_id: u64,
        escrow_id: u64,
        current_time: u64
    ) {
        let order = table::borrow_mut(&mut registry.dvp_orders, order_id);
        let escrow = table::borrow(&registry.dvp_escrows, escrow_id);
        
        let settlement_id = registry.next_settlement_id;
        registry.next_settlement_id = registry.next_settlement_id + 1;
        
        let settlement = DVPSettlement {
            settlement_id,
            order_id,
            seller: order.seller,
            buyer: order.buyer,
            token_address: order.token_address,
            token_amount: order.token_amount,
            payment_amount: order.payment_amount,
            payment_token_address: order.payment_token_address,
            status: 1, // Completed
            settled_at: current_time,
        };
        
        table::add(&mut registry.dvp_settlements, settlement_id, settlement);
        
        // Update order status
        order.status = constants::get_dvp_order_status_executed();
        order.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut registry.dvp_settlement_completed_events, DVPSettlementCompletedEvent {
            settlement_id,
            order_id,
            seller: order.seller,
            buyer: order.buyer,
            token_address: order.token_address,
            token_amount: order.token_amount,
            payment_amount: order.payment_amount,
            payment_token_address: order.payment_token_address,
            settled_at: current_time,
        });
    }

    // ========== VIEW FUNCTIONS ==========
    
    /// Get DVP order information
    public fun get_dvp_order(order_id: u64): (address, address, address, u64, u64, address, u8, u64, u64, u64) acquires DVPManagerRegistry {
        // Note: This function needs admin address to access registry
        // For now, we'll use a placeholder - this needs to be refactored
        let registry = borrow_global<DVPManagerRegistry>(@0x1);
        assert!(table::contains(&registry.dvp_orders, order_id), constants::get_dvp_order_not_found_error());
        
        let order = table::borrow(&registry.dvp_orders, order_id);
        (
            order.seller,
            order.buyer,
            order.token_address,
            order.token_amount,
            order.payment_amount,
            order.payment_token_address,
            order.status,
            order.expiry,
            order.created_at,
            order.updated_at,
        )
    }
    
    /// Get DVP escrow information
    public fun get_dvp_escrow(escrow_id: u64): (u64, address, address, address, u64, u64, address, u8, u64, u64) acquires DVPManagerRegistry {
        // Note: This function needs admin address to access registry
        // For now, we'll use a placeholder - this needs to be refactored
        let registry = borrow_global<DVPManagerRegistry>(@0x1);
        assert!(table::contains(&registry.dvp_escrows, escrow_id), constants::get_dvp_escrow_not_found_error());
        
        let escrow = table::borrow(&registry.dvp_escrows, escrow_id);
        (
            escrow.order_id,
            escrow.seller,
            escrow.buyer,
            escrow.token_address,
            escrow.token_amount,
            escrow.payment_amount,
            escrow.payment_token_address,
            escrow.status,
            escrow.created_at,
            escrow.updated_at,
        )
    }
    
    /// Get DVP settlement information
    public fun get_dvp_settlement(settlement_id: u64): (u64, address, address, address, u64, u64, address, u8, u64) acquires DVPManagerRegistry {
        // Note: This function needs admin address to access registry
        // For now, we'll use a placeholder - this needs to be refactored
        let registry = borrow_global<DVPManagerRegistry>(@0x1);
        assert!(table::contains(&registry.dvp_settlements, settlement_id), constants::get_dvp_settlement_failed_error());
        
        let settlement = table::borrow(&registry.dvp_settlements, settlement_id);
        (
            settlement.order_id,
            settlement.seller,
            settlement.buyer,
            settlement.token_address,
            settlement.token_amount,
            settlement.payment_amount,
            settlement.payment_token_address,
            settlement.status,
            settlement.settled_at,
        )
    }
    
    /// Check DVP order status
    public fun check_dvp_order_status(order_id: u64): u8 acquires DVPManagerRegistry {
        // Note: This function needs admin address to access registry
        // For now, we'll use a placeholder - this needs to be refactored
        let registry = borrow_global<DVPManagerRegistry>(@0x1);
        assert!(table::contains(&registry.dvp_orders, order_id), constants::get_dvp_order_not_found_error());
        
        let order = table::borrow(&registry.dvp_orders, order_id);
        order.status
    }
    
    /// Get user's DVP orders
    public fun get_user_dvp_orders(user: address): vector<u64> acquires DVPManagerRegistry {
        let registry = borrow_global<DVPManagerRegistry>(@0x1);
        
        if (!table::contains(&registry.user_orders, user)) {
            return vector::empty()
        };
        
        *table::borrow(&registry.user_orders, user)
    }
    
    /// Check if DVP order exists
    public fun does_dvp_order_exist(order_id: u64): bool acquires DVPManagerRegistry {
        // Note: This function needs admin address to access registry
        // For now, we'll use a placeholder - this needs to be refactored
        let registry = borrow_global<DVPManagerRegistry>(@0x1);
        table::contains(&registry.dvp_orders, order_id)
    }
    
    /// Check if DVP order is expired
    public fun is_dvp_order_expired(order_id: u64): bool acquires DVPManagerRegistry {
        // Note: This function needs admin address to access registry
        // For now, we'll use a placeholder - this needs to be refactored
        let registry = borrow_global<DVPManagerRegistry>(@0x1);
        assert!(table::contains(&registry.dvp_orders, order_id), constants::get_dvp_order_not_found_error());
        
        let order = table::borrow(&registry.dvp_orders, order_id);
        let current_time = timestamp::now_seconds();
        current_time > order.expiry
    }
    
    /// Get next order ID
    public fun get_next_order_id(): u64 acquires DVPManagerRegistry {
        // Note: This function needs admin address to access registry
        // For now, we'll use a placeholder - this needs to be refactored
        let registry = borrow_global<DVPManagerRegistry>(@0x1);
        registry.next_order_id
    }
    
    /// Get next escrow ID
    public fun get_next_escrow_id(): u64 acquires DVPManagerRegistry {
        // Note: This function needs admin address to access registry
        // For now, we'll use a placeholder - this needs to be refactored
        let registry = borrow_global<DVPManagerRegistry>(@0x1);
        registry.next_escrow_id
    }
    
    /// Get next settlement ID
    public fun get_next_settlement_id(): u64 acquires DVPManagerRegistry {
        // Note: This function needs admin address to access registry
        // For now, we'll use a placeholder - this needs to be refactored
        let registry = borrow_global<DVPManagerRegistry>(@0x1);
        registry.next_settlement_id
    }
    
    /// Get total number of DVP orders
    public fun get_total_dvp_orders(): u64 acquires DVPManagerRegistry {
        // Note: This function needs admin address to access registry
        // For now, we'll use a placeholder - this needs to be refactored
        let registry = borrow_global<DVPManagerRegistry>(@0x1);
        registry.next_order_id - 1
    }
    
    /// Get total number of DVP escrows
    public fun get_total_dvp_escrows(): u64 acquires DVPManagerRegistry {
        // Note: This function needs admin address to access registry
        // For now, we'll use a placeholder - this needs to be refactored
        let registry = borrow_global<DVPManagerRegistry>(@0x1);
        registry.next_escrow_id - 1
    }
    
    /// Get total number of DVP settlements
    public fun get_total_dvp_settlements(): u64 acquires DVPManagerRegistry {
        // Note: This function needs admin address to access registry
        // For now, we'll use a placeholder - this needs to be refactored
        let registry = borrow_global<DVPManagerRegistry>(@0x1);
        registry.next_settlement_id - 1
    }
}
