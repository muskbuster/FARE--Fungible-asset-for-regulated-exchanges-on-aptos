/// DVE Exchange module for T-REX compliant token system
/// Implements Delivery vs Exchange (DVE) functionality

module FARE::dve_exchange {
    use std::vector;
    use std::string::{Self, String};
    use std::table::{Self, Table};
    use std::error;
    use std::signer;
    use std::timestamp;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;
    use FARE::constants;
    use FARE::trex_token;
    use FARE::onchain_identity;

    // ========== STRUCTS ==========
    
    /// Exchange information
    struct ExchangeInfo has store, copy, drop {
        /// Exchange address
        exchange_address: address,
        /// Exchange name
        name: String,
        /// Exchange URL
        url: String,
        /// Compliance level
        compliance_level: u8,
        /// Whether exchange is active
        is_active: bool,
        /// Exchange-specific transfer limits
        transfer_limits: vector<u8>,
        /// Settlement delays for exchange transfers
        settlement_delay: u64,
        /// Netting capabilities enabled
        netting_enabled: bool,
        /// Daily volume limit
        daily_volume_limit: u64,
        /// Monthly volume limit
        monthly_volume_limit: u64,
        /// Current daily volume
        current_daily_volume: u64,
        /// Current monthly volume
        current_monthly_volume: u64,
        /// Last reset date for daily volume
        last_daily_reset: u64,
        /// Last reset date for monthly volume
        last_monthly_reset: u64,
        /// Created timestamp
        created_at: u64,
        /// Last updated timestamp
        updated_at: u64,
    }
    
    /// DVE order information
    struct DVEOrder has store, copy, drop {
        /// Order ID
        order_id: u64,
        /// Exchange address
        exchange_address: address,
        /// User address
        user_address: address,
        /// Token address
        token_address: address,
        /// Token amount
        token_amount: u64,
        /// Order type (buy/sell)
        order_type: u8,
        /// Order status
        status: u8,
        /// Order expiry timestamp
        expiry: u64,
        /// Created timestamp
        created_at: u64,
        /// Last updated timestamp
        updated_at: u64,
    }
    
    /// DVE settlement information
    struct DVESettlement has store, copy, drop {
        /// Settlement ID
        settlement_id: u64,
        /// Exchange address
        exchange_address: address,
        /// User address
        user_address: address,
        /// Token address
        token_address: address,
        /// Token amount
        token_amount: u64,
        /// Settlement type
        settlement_type: u8,
        /// Settlement status
        status: u8,
        /// Settlement delay
        settlement_delay: u64,
        /// Settlement timestamp
        settled_at: u64,
    }
    
    /// Netting information
    struct NettingInfo has store, copy, drop {
        /// Netting ID
        netting_id: u64,
        /// Exchange address
        exchange_address: address,
        /// User address
        user_address: address,
        /// Token address
        token_address: address,
        /// Net amount
        net_amount: u64,
        /// Netting status
        status: u8,
        /// Netting timestamp
        netted_at: u64,
    }
    
    /// DVE exchange registry
    struct DVEExchangeRegistry has key {
        /// Map of exchange address to exchange info
        exchanges: Table<address, ExchangeInfo>,
        /// Map of order ID to DVE order
        dve_orders: Table<u64, DVEOrder>,
        /// Map of settlement ID to DVE settlement
        dve_settlements: Table<u64, DVESettlement>,
        /// Map of netting ID to netting info
        netting_info: Table<u64, NettingInfo>,
        /// Map of user to their orders
        user_orders: Table<address, vector<u64>>,
        /// Next order ID
        next_order_id: u64,
        /// Next settlement ID
        next_settlement_id: u64,
        /// Next netting ID
        next_netting_id: u64,
        /// Events
        exchange_registered_events: EventHandle<ExchangeRegisteredEvent>,
        exchange_updated_events: EventHandle<ExchangeUpdatedEvent>,
        dve_order_created_events: EventHandle<DVEOrderCreatedEvent>,
        dve_order_executed_events: EventHandle<DVEOrderExecutedEvent>,
        dve_settlement_completed_events: EventHandle<DVESettlementCompletedEvent>,
        netting_completed_events: EventHandle<NettingCompletedEvent>,
    }
    
    /// Exchange registered event
    struct ExchangeRegisteredEvent has store, drop {
        exchange_address: address,
        name: String,
        url: String,
        compliance_level: u8,
        registered_at: u64,
    }
    
    /// Exchange updated event
    struct ExchangeUpdatedEvent has store, drop {
        exchange_address: address,
        updated_by: address,
        updated_at: u64,
    }
    
    /// DVE order created event
    struct DVEOrderCreatedEvent has store, drop {
        order_id: u64,
        exchange_address: address,
        user_address: address,
        token_address: address,
        token_amount: u64,
        order_type: u8,
        expiry: u64,
        created_at: u64,
    }
    
    /// DVE order executed event
    struct DVEOrderExecutedEvent has store, drop {
        order_id: u64,
        exchange_address: address,
        user_address: address,
        token_address: address,
        token_amount: u64,
        executed_at: u64,
    }
    
    /// DVE settlement completed event
    struct DVESettlementCompletedEvent has store, drop {
        settlement_id: u64,
        exchange_address: address,
        user_address: address,
        token_address: address,
        token_amount: u64,
        settlement_type: u8,
        settled_at: u64,
    }
    
    /// Netting completed event
    struct NettingCompletedEvent has store, drop {
        netting_id: u64,
        exchange_address: address,
        user_address: address,
        token_address: address,
        net_amount: u64,
        netted_at: u64,
    }

    // ========== INITIALIZATION ==========
    
    /// Initialize DVE exchange registry
    public fun initialize(account: &signer) {
        let account_addr = signer::address_of(account);
        
        // Ensure account is not already initialized
        assert!(!exists<DVEExchangeRegistry>(account_addr), constants::get_access_control_not_authorized_error());
        
        let registry = DVEExchangeRegistry {
            exchanges: table::new(),
            dve_orders: table::new(),
            dve_settlements: table::new(),
            netting_info: table::new(),
            user_orders: table::new(),
            next_order_id: 1,
            next_settlement_id: 1,
            next_netting_id: 1,
            exchange_registered_events: account::new_event_handle<ExchangeRegisteredEvent>(account),
            exchange_updated_events: account::new_event_handle<ExchangeUpdatedEvent>(account),
            dve_order_created_events: account::new_event_handle<DVEOrderCreatedEvent>(account),
            dve_order_executed_events: account::new_event_handle<DVEOrderExecutedEvent>(account),
            dve_settlement_completed_events: account::new_event_handle<DVESettlementCompletedEvent>(account),
            netting_completed_events: account::new_event_handle<NettingCompletedEvent>(account),
        };
        
        move_to(account, registry);
    }

    // ========== EXCHANGE MANAGEMENT ==========
    
    /// Register a new exchange
    public fun register_exchange(
        account: &signer,
        exchange_address: address,
        name: String,
        url: String,
        compliance_level: u8,
        transfer_limits: vector<u8>,
        settlement_delay: u64,
        netting_enabled: bool,
        daily_volume_limit: u64,
        monthly_volume_limit: u64
    ) acquires DVEExchangeRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<DVEExchangeRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if exchange is already registered
        assert!(!table::contains(&registry.exchanges, exchange_address), constants::get_dvp_exchange_not_registered_error());
        
        // Validate compliance level
        assert!(compliance_level >= constants::get_exchange_compliance_basic() && 
                compliance_level <= constants::get_exchange_compliance_full(), constants::get_invalid_parameter_error());
        
        // Validate parameters
        assert!(constants::is_valid_duration(settlement_delay), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_amount(daily_volume_limit), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_amount(monthly_volume_limit), constants::get_invalid_parameter_error());
        
        let exchange_info = ExchangeInfo {
            exchange_address,
            name,
            url,
            compliance_level,
            is_active: true,
            transfer_limits,
            settlement_delay,
            netting_enabled,
            daily_volume_limit,
            monthly_volume_limit,
            current_daily_volume: 0,
            current_monthly_volume: 0,
            last_daily_reset: current_time,
            last_monthly_reset: current_time,
            created_at: current_time,
            updated_at: current_time,
        };
        
        table::add(&mut registry.exchanges, exchange_address, exchange_info);
        
        // Emit event
        event::emit_event(&mut registry.exchange_registered_events, ExchangeRegisteredEvent {
            exchange_address,
            name,
            url,
            compliance_level,
            registered_at: current_time,
        });
    }
    
    /// Update exchange information
    public fun update_exchange(
        account: &signer,
        exchange_address: address,
        name: String,
        url: String,
        compliance_level: u8,
        transfer_limits: vector<u8>,
        settlement_delay: u64,
        netting_enabled: bool,
        daily_volume_limit: u64,
        monthly_volume_limit: u64
    ) acquires DVEExchangeRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<DVEExchangeRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if exchange exists
        assert!(table::contains(&registry.exchanges, exchange_address), constants::get_dvp_exchange_not_registered_error());
        
        // Validate compliance level
        assert!(compliance_level >= constants::get_exchange_compliance_basic() && 
                compliance_level <= constants::get_exchange_compliance_full(), constants::get_invalid_parameter_error());
        
        // Validate parameters
        assert!(constants::is_valid_duration(settlement_delay), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_amount(daily_volume_limit), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_amount(monthly_volume_limit), constants::get_invalid_parameter_error());
        
        let exchange_info = table::borrow_mut(&mut registry.exchanges, exchange_address);
        exchange_info.name = name;
        exchange_info.url = url;
        exchange_info.compliance_level = compliance_level;
        exchange_info.transfer_limits = transfer_limits;
        exchange_info.settlement_delay = settlement_delay;
        exchange_info.netting_enabled = netting_enabled;
        exchange_info.daily_volume_limit = daily_volume_limit;
        exchange_info.monthly_volume_limit = monthly_volume_limit;
        exchange_info.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut registry.exchange_updated_events, ExchangeUpdatedEvent {
            exchange_address,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }
    
    /// Deactivate exchange
    public fun deactivate_exchange(
        account: &signer,
        exchange_address: address
    ) acquires DVEExchangeRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<DVEExchangeRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if exchange exists
        assert!(table::contains(&registry.exchanges, exchange_address), constants::get_dvp_exchange_not_registered_error());
        
        let exchange_info = table::borrow_mut(&mut registry.exchanges, exchange_address);
        exchange_info.is_active = false;
        exchange_info.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut registry.exchange_updated_events, ExchangeUpdatedEvent {
            exchange_address,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }

    // ========== DVE ORDER MANAGEMENT ==========
    
    /// Create a new DVE order
    public fun create_dve_order(
        account: &signer,
        exchange_address: address,
        token_address: address,
        token_amount: u64,
        order_type: u8,
        expiry: u64
    ): u64 acquires DVEExchangeRegistry {
        let user = signer::address_of(account);
        let registry = borrow_global_mut<DVEExchangeRegistry>(user);
        let current_time = timestamp::now_seconds();
        
        // Validate parameters
        assert!(constants::is_valid_amount(token_amount), constants::get_invalid_parameter_error());
        assert!(expiry > current_time, constants::get_invalid_parameter_error());
        
        // Check if exchange is registered and active
        assert!(table::contains(&registry.exchanges, exchange_address), constants::get_dvp_exchange_not_registered_error());
        let exchange_info = table::borrow(&registry.exchanges, exchange_address);
        assert!(exchange_info.is_active, constants::get_dvp_exchange_not_registered_error());
        
        // Check if token is T-REX compliant
        assert!(trex_token::is_trex_compliant(token_address), constants::get_compliance_check_failed_error());
        
        // Check if user has identity if required
        if (onchain_identity::has_identity(user)) {
            let (_, kyc_level, investor_type, _, _, _, _) = onchain_identity::get_identity_status(user);
            // Additional identity checks can be added here
        };
        
        let order_id = registry.next_order_id;
        registry.next_order_id = registry.next_order_id + 1;
        
        let order = DVEOrder {
            order_id,
            exchange_address,
            user_address: user,
            token_address,
            token_amount,
            order_type,
            status: 1, // Pending
            expiry,
            created_at: current_time,
            updated_at: current_time,
        };
        
        table::add(&mut registry.dve_orders, order_id, order);
        
        // Add to user orders
        if (!table::contains(&registry.user_orders, user)) {
            table::add(&mut registry.user_orders, user, vector::empty());
        };
        let user_orders = table::borrow_mut(&mut registry.user_orders, user);
        vector::push_back(user_orders, order_id);
        
        // Emit event
        event::emit_event(&mut registry.dve_order_created_events, DVEOrderCreatedEvent {
            order_id,
            exchange_address,
            user_address: user,
            token_address,
            token_amount,
            order_type,
            expiry,
            created_at: current_time,
        });
        
        order_id
    }
    
    /// Execute a DVE order
    public fun execute_dve_order(
        account: &signer,
        order_id: u64
    ) acquires DVEExchangeRegistry {
        let executor = signer::address_of(account);
        let registry = borrow_global_mut<DVEExchangeRegistry>(executor);
        let current_time = timestamp::now_seconds();
        
        // Check if order exists
        assert!(table::contains(&registry.dve_orders, order_id), constants::get_dvp_order_not_found_error());
        
        let order = table::borrow_mut(&mut registry.dve_orders, order_id);
        
        // Check if order is still pending
        assert!(order.status == 1, constants::get_dvp_order_already_executed_error());
        
        // Check if order has not expired
        assert!(current_time <= order.expiry, constants::get_dvp_order_expired_error());
        
        // Check if executor is the user who created the order
        assert!(order.user_address == executor, constants::get_access_control_not_authorized_error());
        
        // Copy values before calling functions to avoid borrow checker issues
        let exchange_address = order.exchange_address;
        let user_address = order.user_address;
        let token_address = order.token_address;
        let token_amount = order.token_amount;
        
        // Update order status
        order.status = 2; // Executed
        order.updated_at = current_time;
        
        // Create settlement
        create_settlement_internal(registry, order_id, current_time);
        
        // Update exchange volume
        update_exchange_volume(registry, exchange_address, token_amount, current_time);
        
        // Emit event
        event::emit_event(&mut registry.dve_order_executed_events, DVEOrderExecutedEvent {
            order_id,
            exchange_address,
            user_address,
            token_address,
            token_amount,
            executed_at: current_time,
        });
    }
    
    /// Create settlement (internal function)
    fun create_settlement_internal(
        registry: &mut DVEExchangeRegistry,
        order_id: u64,
        current_time: u64
    ) {
        let order = table::borrow(&registry.dve_orders, order_id);
        let exchange_info = table::borrow(&registry.exchanges, order.exchange_address);
        
        let settlement_id = registry.next_settlement_id;
        registry.next_settlement_id = registry.next_settlement_id + 1;
        
        let settlement = DVESettlement {
            settlement_id,
            exchange_address: order.exchange_address,
            user_address: order.user_address,
            token_address: order.token_address,
            token_amount: order.token_amount,
            settlement_type: order.order_type,
            status: 1, // Pending
            settlement_delay: exchange_info.settlement_delay,
            settled_at: current_time + exchange_info.settlement_delay,
        };
        
        table::add(&mut registry.dve_settlements, settlement_id, settlement);
        
        // Emit event
        event::emit_event(&mut registry.dve_settlement_completed_events, DVESettlementCompletedEvent {
            settlement_id,
            exchange_address: order.exchange_address,
            user_address: order.user_address,
            token_address: order.token_address,
            token_amount: order.token_amount,
            settlement_type: order.order_type,
            settled_at: current_time + exchange_info.settlement_delay,
        });
    }
    
    /// Update exchange volume (internal function)
    fun update_exchange_volume(
        registry: &mut DVEExchangeRegistry,
        exchange_address: address,
        amount: u64,
        current_time: u64
    ) {
        let exchange_info = table::borrow_mut(&mut registry.exchanges, exchange_address);
        
        // Reset daily volume if needed
        if (current_time - exchange_info.last_daily_reset >= 86400) { // 24 hours
            exchange_info.current_daily_volume = 0;
            exchange_info.last_daily_reset = current_time;
        };
        
        // Reset monthly volume if needed
        if (current_time - exchange_info.last_monthly_reset >= 2592000) { // 30 days
            exchange_info.current_monthly_volume = 0;
            exchange_info.last_monthly_reset = current_time;
        };
        
        // Update volumes
        exchange_info.current_daily_volume = exchange_info.current_daily_volume + amount;
        exchange_info.current_monthly_volume = exchange_info.current_monthly_volume + amount;
    }

    // ========== NETTING MANAGEMENT ==========
    
    /// Perform netting for a user
    public fun perform_netting(
        account: &signer,
        exchange_address: address,
        user_address: address,
        token_address: address
    ) acquires DVEExchangeRegistry {
        let netter = signer::address_of(account);
        let registry = borrow_global_mut<DVEExchangeRegistry>(netter);
        let current_time = timestamp::now_seconds();
        
        // Check if exchange exists and is active
        assert!(table::contains(&registry.exchanges, exchange_address), constants::get_dvp_exchange_not_registered_error());
        let exchange_info = table::borrow(&registry.exchanges, exchange_address);
        assert!(exchange_info.is_active, constants::get_dvp_exchange_not_registered_error());
        assert!(exchange_info.netting_enabled, constants::get_dvp_exchange_not_registered_error());
        
        // Calculate net amount
        let net_amount = calculate_net_amount(registry, exchange_address, user_address, token_address);
        
        if (net_amount > 0) {
            let netting_id = registry.next_netting_id;
            registry.next_netting_id = registry.next_netting_id + 1;
            
            let netting = NettingInfo {
                netting_id,
                exchange_address,
                user_address,
                token_address,
                net_amount,
                status: 1, // Completed
                netted_at: current_time,
            };
            
            table::add(&mut registry.netting_info, netting_id, netting);
            
            // Emit event
            event::emit_event(&mut registry.netting_completed_events, NettingCompletedEvent {
                netting_id,
                exchange_address,
                user_address,
                token_address,
                net_amount,
                netted_at: current_time,
            });
        };
    }
    
    /// Calculate net amount (internal function)
    fun calculate_net_amount(
        registry: &DVEExchangeRegistry,
        exchange_address: address,
        user_address: address,
        token_address: address
    ): u64 {
        // This is a simplified implementation
        // In a real implementation, you would calculate the net amount
        // based on all pending settlements for the user
        0
    }

    // ========== VIEW FUNCTIONS ==========
    
    /// Get exchange information
    public fun get_exchange_info(exchange_address: address): (String, String, u8, bool, vector<u8>, u64, bool, u64, u64, u64, u64, u64, u64, u64) acquires DVEExchangeRegistry {
        let registry = borrow_global<DVEExchangeRegistry>(exchange_address);
        assert!(table::contains(&registry.exchanges, exchange_address), constants::get_dvp_exchange_not_registered_error());
        
        let exchange_info = table::borrow(&registry.exchanges, exchange_address);
        (
            exchange_info.name,
            exchange_info.url,
            exchange_info.compliance_level,
            exchange_info.is_active,
            exchange_info.transfer_limits,
            exchange_info.settlement_delay,
            exchange_info.netting_enabled,
            exchange_info.daily_volume_limit,
            exchange_info.monthly_volume_limit,
            exchange_info.current_daily_volume,
            exchange_info.current_monthly_volume,
            exchange_info.last_daily_reset,
            exchange_info.last_monthly_reset,
            exchange_info.created_at,
        )
    }
    
    /// Get DVE order information
    public fun get_dve_order(order_id: u64): (address, address, address, u64, u8, u8, u64, u64, u64) acquires DVEExchangeRegistry {
        let registry = borrow_global<DVEExchangeRegistry>(@0x0); // This will need to be updated with actual address
        assert!(table::contains(&registry.dve_orders, order_id), constants::get_dvp_order_not_found_error());
        
        let order = table::borrow(&registry.dve_orders, order_id);
        (
            order.exchange_address,
            order.user_address,
            order.token_address,
            order.token_amount,
            order.order_type,
            order.status,
            order.expiry,
            order.created_at,
            order.updated_at,
        )
    }
    
    /// Get DVE settlement information
    public fun get_dve_settlement(settlement_id: u64): (address, address, address, u64, u8, u8, u64, u64) acquires DVEExchangeRegistry {
        let registry = borrow_global<DVEExchangeRegistry>(@0x0); // This will need to be updated with actual address
        assert!(table::contains(&registry.dve_settlements, settlement_id), constants::get_dvp_settlement_failed_error());
        
        let settlement = table::borrow(&registry.dve_settlements, settlement_id);
        (
            settlement.exchange_address,
            settlement.user_address,
            settlement.token_address,
            settlement.token_amount,
            settlement.settlement_type,
            settlement.status,
            settlement.settlement_delay,
            settlement.settled_at,
        )
    }
    
    /// Get netting information
    public fun get_netting_info(netting_id: u64): (address, address, address, u64, u8, u64) acquires DVEExchangeRegistry {
        let registry = borrow_global<DVEExchangeRegistry>(@0x0); // This will need to be updated with actual address
        assert!(table::contains(&registry.netting_info, netting_id), constants::get_dvp_settlement_failed_error());
        
        let netting = table::borrow(&registry.netting_info, netting_id);
        (
            netting.exchange_address,
            netting.user_address,
            netting.token_address,
            netting.net_amount,
            netting.status,
            netting.netted_at,
        )
    }
    
    /// Check if exchange is registered
    public fun is_exchange_registered(exchange_address: address): bool acquires DVEExchangeRegistry {
        let registry = borrow_global<DVEExchangeRegistry>(exchange_address);
        table::contains(&registry.exchanges, exchange_address)
    }
    
    /// Check if exchange is active
    public fun is_exchange_active(exchange_address: address): bool acquires DVEExchangeRegistry {
        let registry = borrow_global<DVEExchangeRegistry>(exchange_address);
        
        if (!table::contains(&registry.exchanges, exchange_address)) {
            return false
        };
        
        let exchange_info = table::borrow(&registry.exchanges, exchange_address);
        exchange_info.is_active
    }
    
    /// Get user's DVE orders
    public fun get_user_dve_orders(user: address): vector<u64> acquires DVEExchangeRegistry {
        let registry = borrow_global<DVEExchangeRegistry>(user);
        
        if (!table::contains(&registry.user_orders, user)) {
            return vector::empty()
        };
        
        *table::borrow(&registry.user_orders, user)
    }
    
    /// Get exchange compliance level
    public fun get_exchange_compliance_level(exchange_address: address): u8 acquires DVEExchangeRegistry {
        let registry = borrow_global<DVEExchangeRegistry>(exchange_address);
        assert!(table::contains(&registry.exchanges, exchange_address), constants::get_dvp_exchange_not_registered_error());
        
        let exchange_info = table::borrow(&registry.exchanges, exchange_address);
        exchange_info.compliance_level
    }
    
    /// Check if exchange has sufficient compliance level
    public fun has_sufficient_compliance_level(exchange_address: address, required_level: u8): bool acquires DVEExchangeRegistry {
        let registry = borrow_global<DVEExchangeRegistry>(exchange_address);
        
        if (!table::contains(&registry.exchanges, exchange_address)) {
            return false
        };
        
        let exchange_info = table::borrow(&registry.exchanges, exchange_address);
        exchange_info.compliance_level >= required_level
    }
    
    /// Get exchange daily volume
    public fun get_exchange_daily_volume(exchange_address: address): u64 acquires DVEExchangeRegistry {
        let registry = borrow_global<DVEExchangeRegistry>(exchange_address);
        assert!(table::contains(&registry.exchanges, exchange_address), constants::get_dvp_exchange_not_registered_error());
        
        let exchange_info = table::borrow(&registry.exchanges, exchange_address);
        exchange_info.current_daily_volume
    }
    
    /// Get exchange monthly volume
    public fun get_exchange_monthly_volume(exchange_address: address): u64 acquires DVEExchangeRegistry {
        let registry = borrow_global<DVEExchangeRegistry>(exchange_address);
        assert!(table::contains(&registry.exchanges, exchange_address), constants::get_dvp_exchange_not_registered_error());
        
        let exchange_info = table::borrow(&registry.exchanges, exchange_address);
        exchange_info.current_monthly_volume
    }
    
    /// Check if exchange has reached daily volume limit
    public fun has_exchange_reached_daily_limit(exchange_address: address): bool acquires DVEExchangeRegistry {
        let registry = borrow_global<DVEExchangeRegistry>(exchange_address);
        assert!(table::contains(&registry.exchanges, exchange_address), constants::get_dvp_exchange_not_registered_error());
        
        let exchange_info = table::borrow(&registry.exchanges, exchange_address);
        exchange_info.current_daily_volume >= exchange_info.daily_volume_limit
    }
    
    /// Check if exchange has reached monthly volume limit
    public fun has_exchange_reached_monthly_limit(exchange_address: address): bool acquires DVEExchangeRegistry {
        let registry = borrow_global<DVEExchangeRegistry>(exchange_address);
        assert!(table::contains(&registry.exchanges, exchange_address), constants::get_dvp_exchange_not_registered_error());
        
        let exchange_info = table::borrow(&registry.exchanges, exchange_address);
        exchange_info.current_monthly_volume >= exchange_info.monthly_volume_limit
    }
}
