/// Token Information module for T-REX compliant token system
/// Manages token metadata and information

module FARE::token_information {
    use std::vector;
    use std::string::{Self, String};
    use std::table::{Self, Table};
    use std::error;
    use std::signer;
    use std::timestamp;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;
    use aptos_framework::fungible_asset::{Self, FungibleAsset};
    use aptos_framework::primary_fungible_store;
    use FARE::constants;

    // ========== STRUCTS ==========
    
    /// Token metadata information
    struct TokenMetadata has store, copy, drop {
        /// Token name
        name: String,
        /// Token symbol
        symbol: String,
        /// Token description
        description: String,
        /// Token decimals
        decimals: u8,
        /// Token icon URI
        icon_uri: String,
        /// Token project URI
        project_uri: String,
        /// Token creator
        creator: address,
        /// Token creation timestamp
        created_at: u64,
        /// Last updated timestamp
        updated_at: u64,
    }
    
    /// Token supply information
    struct TokenSupplyInfo has store, copy, drop {
        /// Current supply
        current_supply: u64,
        /// Maximum supply (0 = unlimited)
        max_supply: u64,
        /// Total minted
        total_minted: u64,
        /// Total burned
        total_burned: u64,
        /// Supply cap enabled
        supply_cap_enabled: bool,
        /// Last updated timestamp
        updated_at: u64,
    }
    
    /// Token compliance information
    struct TokenComplianceInfo has store, copy, drop {
        /// Whether token is T-REX compliant
        is_trex_compliant: bool,
        /// Compliance level
        compliance_level: u8,
        /// Required KYC level
        required_kyc_level: u8,
        /// Required investor type
        required_investor_type: u8,
        /// Country restrictions enabled
        country_restrictions_enabled: bool,
        /// Transfer restrictions enabled
        transfer_restrictions_enabled: bool,
        /// Balance restrictions enabled
        balance_restrictions_enabled: bool,
        /// Last updated timestamp
        updated_at: u64,
    }
    
    /// Token status information
    struct TokenStatusInfo has store, copy, drop {
        /// Whether token is active
        is_active: bool,
        /// Whether token is paused
        is_paused: bool,
        /// Whether token is frozen
        is_frozen: bool,
        /// Pause reason
        pause_reason: String,
        /// Freeze reason
        freeze_reason: String,
        /// Last updated timestamp
        updated_at: u64,
    }
    
    /// Token information registry
    struct TokenInformationRegistry has key {
        /// Map of token address to metadata
        token_metadata: Table<address, TokenMetadata>,
        /// Map of token address to supply info
        token_supply_info: Table<address, TokenSupplyInfo>,
        /// Map of token address to compliance info
        token_compliance_info: Table<address, TokenComplianceInfo>,
        /// Map of token address to status info
        token_status_info: Table<address, TokenStatusInfo>,
        /// Events
        token_metadata_updated_events: EventHandle<TokenMetadataUpdatedEvent>,
        token_supply_updated_events: EventHandle<TokenSupplyUpdatedEvent>,
        token_compliance_updated_events: EventHandle<TokenComplianceUpdatedEvent>,
        token_status_updated_events: EventHandle<TokenStatusUpdatedEvent>,
    }
    
    /// Token metadata updated event
    struct TokenMetadataUpdatedEvent has store, drop {
        token_address: address,
        name: String,
        symbol: String,
        updated_by: address,
        updated_at: u64,
    }
    
    /// Token supply updated event
    struct TokenSupplyUpdatedEvent has store, drop {
        token_address: address,
        current_supply: u64,
        max_supply: u64,
        updated_by: address,
        updated_at: u64,
    }
    
    /// Token compliance updated event
    struct TokenComplianceUpdatedEvent has store, drop {
        token_address: address,
        compliance_level: u8,
        required_kyc_level: u8,
        updated_by: address,
        updated_at: u64,
    }
    
    /// Token status updated event
    struct TokenStatusUpdatedEvent has store, drop {
        token_address: address,
        is_active: bool,
        is_paused: bool,
        is_frozen: bool,
        updated_by: address,
        updated_at: u64,
    }

    // ========== INITIALIZATION ==========
    
    /// Initialize token information registry
    public fun initialize(account: &signer) {
        let account_addr = signer::address_of(account);
        
        // Ensure account is not already initialized
        assert!(!exists<TokenInformationRegistry>(account_addr), constants::get_access_control_not_authorized_error());
        
        let registry = TokenInformationRegistry {
            token_metadata: table::new(),
            token_supply_info: table::new(),
            token_compliance_info: table::new(),
            token_status_info: table::new(),
            token_metadata_updated_events: account::new_event_handle<TokenMetadataUpdatedEvent>(account),
            token_supply_updated_events: account::new_event_handle<TokenSupplyUpdatedEvent>(account),
            token_compliance_updated_events: account::new_event_handle<TokenComplianceUpdatedEvent>(account),
            token_status_updated_events: account::new_event_handle<TokenStatusUpdatedEvent>(account),
        };
        
        move_to(account, registry);
    }

    // ========== TOKEN METADATA MANAGEMENT ==========
    
    /// Register token metadata
    public fun register_token_metadata(
        account: &signer,
        token_address: address,
        name: String,
        symbol: String,
        description: String,
        decimals: u8,
        icon_uri: String,
        project_uri: String
    ) acquires TokenInformationRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TokenInformationRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if token metadata is already registered
        assert!(!table::contains(&registry.token_metadata, token_address), constants::get_compliance_module_already_exists_error());
        
        // Validate parameters
        assert!(decimals <= 18, constants::get_invalid_parameter_error());
        
        let metadata = TokenMetadata {
            name,
            symbol,
            description,
            decimals,
            icon_uri,
            project_uri,
            creator: account_addr,
            created_at: current_time,
            updated_at: current_time,
        };
        
        table::add(&mut registry.token_metadata, token_address, metadata);
        
        // Emit event
        event::emit_event(&mut registry.token_metadata_updated_events, TokenMetadataUpdatedEvent {
            token_address,
            name,
            symbol,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }
    
    /// Update token metadata
    public fun update_token_metadata(
        account: &signer,
        token_address: address,
        name: String,
        symbol: String,
        description: String,
        icon_uri: String,
        project_uri: String
    ) acquires TokenInformationRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TokenInformationRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if token metadata exists
        assert!(table::contains(&registry.token_metadata, token_address), constants::get_compliance_module_not_found_error());
        
        let metadata = table::borrow_mut(&mut registry.token_metadata, token_address);
        metadata.name = name;
        metadata.symbol = symbol;
        metadata.description = description;
        metadata.icon_uri = icon_uri;
        metadata.project_uri = project_uri;
        metadata.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut registry.token_metadata_updated_events, TokenMetadataUpdatedEvent {
            token_address,
            name,
            symbol,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }

    // ========== TOKEN SUPPLY MANAGEMENT ==========
    
    /// Initialize token supply information
    public fun initialize_token_supply(
        account: &signer,
        token_address: address,
        max_supply: u64,
        supply_cap_enabled: bool
    ) acquires TokenInformationRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TokenInformationRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if token supply info is already initialized
        assert!(!table::contains(&registry.token_supply_info, token_address), constants::get_compliance_module_already_exists_error());
        
        let supply_info = TokenSupplyInfo {
            current_supply: 0,
            max_supply,
            total_minted: 0,
            total_burned: 0,
            supply_cap_enabled,
            updated_at: current_time,
        };
        
        table::add(&mut registry.token_supply_info, token_address, supply_info);
        
        // Emit event
        event::emit_event(&mut registry.token_supply_updated_events, TokenSupplyUpdatedEvent {
            token_address,
            current_supply: 0,
            max_supply,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }
    
    /// Update token supply after mint
    public fun update_supply_after_mint(
        account: &signer,
        token_address: address,
        mint_amount: u64
    ) acquires TokenInformationRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TokenInformationRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if token supply info exists
        assert!(table::contains(&registry.token_supply_info, token_address), constants::get_compliance_module_not_found_error());
        
        let supply_info = table::borrow_mut(&mut registry.token_supply_info, token_address);
        
        // Check supply cap if enabled
        if (supply_info.supply_cap_enabled && supply_info.max_supply > 0) {
            assert!(supply_info.current_supply + mint_amount <= supply_info.max_supply, constants::get_token_supply_cap_exceeded_error());
        };
        
        supply_info.current_supply = supply_info.current_supply + mint_amount;
        supply_info.total_minted = supply_info.total_minted + mint_amount;
        supply_info.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut registry.token_supply_updated_events, TokenSupplyUpdatedEvent {
            token_address,
            current_supply: supply_info.current_supply,
            max_supply: supply_info.max_supply,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }
    
    /// Update token supply after burn
    public fun update_supply_after_burn(
        account: &signer,
        token_address: address,
        burn_amount: u64
    ) acquires TokenInformationRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TokenInformationRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if token supply info exists
        assert!(table::contains(&registry.token_supply_info, token_address), constants::get_compliance_module_not_found_error());
        
        let supply_info = table::borrow_mut(&mut registry.token_supply_info, token_address);
        supply_info.current_supply = supply_info.current_supply - burn_amount;
        supply_info.total_burned = supply_info.total_burned + burn_amount;
        supply_info.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut registry.token_supply_updated_events, TokenSupplyUpdatedEvent {
            token_address,
            current_supply: supply_info.current_supply,
            max_supply: supply_info.max_supply,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }
    
    /// Update supply cap
    public fun update_supply_cap(
        account: &signer,
        token_address: address,
        new_max_supply: u64,
        supply_cap_enabled: bool
    ) acquires TokenInformationRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TokenInformationRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if token supply info exists
        assert!(table::contains(&registry.token_supply_info, token_address), constants::get_compliance_module_not_found_error());
        
        let supply_info = table::borrow_mut(&mut registry.token_supply_info, token_address);
        
        // Validate new max supply
        if (supply_cap_enabled && new_max_supply > 0) {
            assert!(supply_info.current_supply <= new_max_supply, constants::get_invalid_parameter_error());
        };
        
        supply_info.max_supply = new_max_supply;
        supply_info.supply_cap_enabled = supply_cap_enabled;
        supply_info.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut registry.token_supply_updated_events, TokenSupplyUpdatedEvent {
            token_address,
            current_supply: supply_info.current_supply,
            max_supply: new_max_supply,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }

    // ========== TOKEN COMPLIANCE MANAGEMENT ==========
    
    /// Initialize token compliance information
    public fun initialize_token_compliance(
        account: &signer,
        token_address: address,
        compliance_level: u8,
        required_kyc_level: u8,
        required_investor_type: u8,
        country_restrictions_enabled: bool,
        transfer_restrictions_enabled: bool,
        balance_restrictions_enabled: bool
    ) acquires TokenInformationRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TokenInformationRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if token compliance info is already initialized
        assert!(!table::contains(&registry.token_compliance_info, token_address), constants::get_compliance_module_already_exists_error());
        
        // Validate parameters
        assert!(constants::is_valid_kyc_level(required_kyc_level), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_investor_type(required_investor_type), constants::get_invalid_parameter_error());
        
        let compliance_info = TokenComplianceInfo {
            is_trex_compliant: true,
            compliance_level,
            required_kyc_level,
            required_investor_type,
            country_restrictions_enabled,
            transfer_restrictions_enabled,
            balance_restrictions_enabled,
            updated_at: current_time,
        };
        
        table::add(&mut registry.token_compliance_info, token_address, compliance_info);
        
        // Emit event
        event::emit_event(&mut registry.token_compliance_updated_events, TokenComplianceUpdatedEvent {
            token_address,
            compliance_level,
            required_kyc_level,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }
    
    /// Update token compliance information
    public fun update_token_compliance(
        account: &signer,
        token_address: address,
        compliance_level: u8,
        required_kyc_level: u8,
        required_investor_type: u8,
        country_restrictions_enabled: bool,
        transfer_restrictions_enabled: bool,
        balance_restrictions_enabled: bool
    ) acquires TokenInformationRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TokenInformationRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if token compliance info exists
        assert!(table::contains(&registry.token_compliance_info, token_address), constants::get_compliance_module_not_found_error());
        
        // Validate parameters
        assert!(constants::is_valid_kyc_level(required_kyc_level), constants::get_invalid_parameter_error());
        assert!(constants::is_valid_investor_type(required_investor_type), constants::get_invalid_parameter_error());
        
        let compliance_info = table::borrow_mut(&mut registry.token_compliance_info, token_address);
        compliance_info.compliance_level = compliance_level;
        compliance_info.required_kyc_level = required_kyc_level;
        compliance_info.required_investor_type = required_investor_type;
        compliance_info.country_restrictions_enabled = country_restrictions_enabled;
        compliance_info.transfer_restrictions_enabled = transfer_restrictions_enabled;
        compliance_info.balance_restrictions_enabled = balance_restrictions_enabled;
        compliance_info.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut registry.token_compliance_updated_events, TokenComplianceUpdatedEvent {
            token_address,
            compliance_level,
            required_kyc_level,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }

    // ========== TOKEN STATUS MANAGEMENT ==========
    
    /// Initialize token status information
    public fun initialize_token_status(
        account: &signer,
        token_address: address
    ) acquires TokenInformationRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TokenInformationRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if token status info is already initialized
        assert!(!table::contains(&registry.token_status_info, token_address), constants::get_compliance_module_already_exists_error());
        
        let status_info = TokenStatusInfo {
            is_active: true,
            is_paused: false,
            is_frozen: false,
            pause_reason: string::utf8(b""),
            freeze_reason: string::utf8(b""),
            updated_at: current_time,
        };
        
        table::add(&mut registry.token_status_info, token_address, status_info);
        
        // Emit event
        event::emit_event(&mut registry.token_status_updated_events, TokenStatusUpdatedEvent {
            token_address,
            is_active: true,
            is_paused: false,
            is_frozen: false,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }
    
    /// Pause token
    public fun pause_token(
        account: &signer,
        token_address: address,
        pause_reason: String
    ) acquires TokenInformationRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TokenInformationRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if token status info exists
        assert!(table::contains(&registry.token_status_info, token_address), constants::get_compliance_module_not_found_error());
        
        let status_info = table::borrow_mut(&mut registry.token_status_info, token_address);
        status_info.is_paused = true;
        status_info.pause_reason = pause_reason;
        status_info.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut registry.token_status_updated_events, TokenStatusUpdatedEvent {
            token_address,
            is_active: status_info.is_active,
            is_paused: true,
            is_frozen: status_info.is_frozen,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }
    
    /// Unpause token
    public fun unpause_token(
        account: &signer,
        token_address: address
    ) acquires TokenInformationRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TokenInformationRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if token status info exists
        assert!(table::contains(&registry.token_status_info, token_address), constants::get_compliance_module_not_found_error());
        
        let status_info = table::borrow_mut(&mut registry.token_status_info, token_address);
        status_info.is_paused = false;
        status_info.pause_reason = string::utf8(b"");
        status_info.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut registry.token_status_updated_events, TokenStatusUpdatedEvent {
            token_address,
            is_active: status_info.is_active,
            is_paused: false,
            is_frozen: status_info.is_frozen,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }
    
    /// Freeze token
    public fun freeze_token(
        account: &signer,
        token_address: address,
        freeze_reason: String
    ) acquires TokenInformationRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TokenInformationRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if token status info exists
        assert!(table::contains(&registry.token_status_info, token_address), constants::get_compliance_module_not_found_error());
        
        let status_info = table::borrow_mut(&mut registry.token_status_info, token_address);
        status_info.is_frozen = true;
        status_info.freeze_reason = freeze_reason;
        status_info.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut registry.token_status_updated_events, TokenStatusUpdatedEvent {
            token_address,
            is_active: status_info.is_active,
            is_paused: status_info.is_paused,
            is_frozen: true,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }
    
    /// Unfreeze token
    public fun unfreeze_token(
        account: &signer,
        token_address: address
    ) acquires TokenInformationRegistry {
        let account_addr = signer::address_of(account);
        let registry = borrow_global_mut<TokenInformationRegistry>(account_addr);
        let current_time = timestamp::now_seconds();
        
        // Check if token status info exists
        assert!(table::contains(&registry.token_status_info, token_address), constants::get_compliance_module_not_found_error());
        
        let status_info = table::borrow_mut(&mut registry.token_status_info, token_address);
        status_info.is_frozen = false;
        status_info.freeze_reason = string::utf8(b"");
        status_info.updated_at = current_time;
        
        // Emit event
        event::emit_event(&mut registry.token_status_updated_events, TokenStatusUpdatedEvent {
            token_address,
            is_active: status_info.is_active,
            is_paused: status_info.is_paused,
            is_frozen: false,
            updated_by: account_addr,
            updated_at: current_time,
        });
    }

    // ========== VIEW FUNCTIONS ==========
    
    /// Get token metadata
    public fun get_token_metadata(token_address: address): (String, String, String, u8, String, String, address, u64, u64) acquires TokenInformationRegistry {
        let registry = borrow_global<TokenInformationRegistry>(token_address);
        assert!(table::contains(&registry.token_metadata, token_address), constants::get_compliance_module_not_found_error());
        
        let metadata = table::borrow(&registry.token_metadata, token_address);
        (
            metadata.name,
            metadata.symbol,
            metadata.description,
            metadata.decimals,
            metadata.icon_uri,
            metadata.project_uri,
            metadata.creator,
            metadata.created_at,
            metadata.updated_at,
        )
    }
    
    /// Get token supply information
    public fun get_token_supply_info(token_address: address): (u64, u64, u64, u64, bool, u64) acquires TokenInformationRegistry {
        let registry = borrow_global<TokenInformationRegistry>(token_address);
        assert!(table::contains(&registry.token_supply_info, token_address), constants::get_compliance_module_not_found_error());
        
        let supply_info = table::borrow(&registry.token_supply_info, token_address);
        (
            supply_info.current_supply,
            supply_info.max_supply,
            supply_info.total_minted,
            supply_info.total_burned,
            supply_info.supply_cap_enabled,
            supply_info.updated_at,
        )
    }
    
    /// Get token compliance information
    public fun get_token_compliance_info(token_address: address): (bool, u8, u8, u8, bool, bool, bool, u64) acquires TokenInformationRegistry {
        let registry = borrow_global<TokenInformationRegistry>(token_address);
        assert!(table::contains(&registry.token_compliance_info, token_address), constants::get_compliance_module_not_found_error());
        
        let compliance_info = table::borrow(&registry.token_compliance_info, token_address);
        (
            compliance_info.is_trex_compliant,
            compliance_info.compliance_level,
            compliance_info.required_kyc_level,
            compliance_info.required_investor_type,
            compliance_info.country_restrictions_enabled,
            compliance_info.transfer_restrictions_enabled,
            compliance_info.balance_restrictions_enabled,
            compliance_info.updated_at,
        )
    }
    
    /// Get token status information
    public fun get_token_status_info(token_address: address): (bool, bool, bool, String, String, u64) acquires TokenInformationRegistry {
        let registry = borrow_global<TokenInformationRegistry>(token_address);
        assert!(table::contains(&registry.token_status_info, token_address), constants::get_compliance_module_not_found_error());
        
        let status_info = table::borrow(&registry.token_status_info, token_address);
        (
            status_info.is_active,
            status_info.is_paused,
            status_info.is_frozen,
            status_info.pause_reason,
            status_info.freeze_reason,
            status_info.updated_at,
        )
    }
    
    /// Check if token is paused
    public fun is_token_paused(token_address: address): bool acquires TokenInformationRegistry {
        let registry = borrow_global<TokenInformationRegistry>(token_address);
        
        if (!table::contains(&registry.token_status_info, token_address)) {
            return false
        };
        
        let status_info = table::borrow(&registry.token_status_info, token_address);
        status_info.is_paused
    }
    
    /// Check if token is frozen
    public fun is_token_frozen(token_address: address): bool acquires TokenInformationRegistry {
        let registry = borrow_global<TokenInformationRegistry>(token_address);
        
        if (!table::contains(&registry.token_status_info, token_address)) {
            return false
        };
        
        let status_info = table::borrow(&registry.token_status_info, token_address);
        status_info.is_frozen
    }
    
    /// Check if token is active
    public fun is_token_active(token_address: address): bool acquires TokenInformationRegistry {
        let registry = borrow_global<TokenInformationRegistry>(token_address);
        
        if (!table::contains(&registry.token_status_info, token_address)) {
            return false
        };
        
        let status_info = table::borrow(&registry.token_status_info, token_address);
        status_info.is_active
    }
    
    /// Check if token is T-REX compliant
    public fun is_token_trex_compliant(token_address: address): bool acquires TokenInformationRegistry {
        let registry = borrow_global<TokenInformationRegistry>(token_address);
        
        if (!table::contains(&registry.token_compliance_info, token_address)) {
            return false
        };
        
        let compliance_info = table::borrow(&registry.token_compliance_info, token_address);
        compliance_info.is_trex_compliant
    }
    
    /// Get token name
    public fun get_token_name(token_address: address): String acquires TokenInformationRegistry {
        let registry = borrow_global<TokenInformationRegistry>(token_address);
        assert!(table::contains(&registry.token_metadata, token_address), constants::get_compliance_module_not_found_error());
        
        let metadata = table::borrow(&registry.token_metadata, token_address);
        metadata.name
    }
    
    /// Get token symbol
    public fun get_token_symbol(token_address: address): String acquires TokenInformationRegistry {
        let registry = borrow_global<TokenInformationRegistry>(token_address);
        assert!(table::contains(&registry.token_metadata, token_address), constants::get_compliance_module_not_found_error());
        
        let metadata = table::borrow(&registry.token_metadata, token_address);
        metadata.symbol
    }
    
    /// Get token decimals
    public fun get_token_decimals(token_address: address): u8 acquires TokenInformationRegistry {
        let registry = borrow_global<TokenInformationRegistry>(token_address);
        assert!(table::contains(&registry.token_metadata, token_address), constants::get_compliance_module_not_found_error());
        
        let metadata = table::borrow(&registry.token_metadata, token_address);
        metadata.decimals
    }
    
    /// Get current token supply
    public fun get_current_supply(token_address: address): u64 acquires TokenInformationRegistry {
        let registry = borrow_global<TokenInformationRegistry>(token_address);
        
        if (!table::contains(&registry.token_supply_info, token_address)) {
            return 0
        };
        
        let supply_info = table::borrow(&registry.token_supply_info, token_address);
        supply_info.current_supply
    }
    
    /// Get maximum token supply
    public fun get_max_supply(token_address: address): u64 acquires TokenInformationRegistry {
        let registry = borrow_global<TokenInformationRegistry>(token_address);
        
        if (!table::contains(&registry.token_supply_info, token_address)) {
            return 0
        };
        
        let supply_info = table::borrow(&registry.token_supply_info, token_address);
        supply_info.max_supply
    }
    
    /// Check if token has supply cap
    public fun has_supply_cap(token_address: address): bool acquires TokenInformationRegistry {
        let registry = borrow_global<TokenInformationRegistry>(token_address);
        
        if (!table::contains(&registry.token_supply_info, token_address)) {
            return false
        };
        
        let supply_info = table::borrow(&registry.token_supply_info, token_address);
        supply_info.supply_cap_enabled
    }
}
