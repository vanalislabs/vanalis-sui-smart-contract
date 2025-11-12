module vanalis::royalty {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use sui::coin::{Coin, Self};
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};

    // CONSTANTS
    const E_INVALID_AMOUNT: u64 = 1;
    const E_INSUFFICIENT_BALANCE: u64 = 2;
    const E_UNAUTHORIZED: u64 = 3;

    // ============= STRUCTS =============

    /// Global royalty tracking
    public struct RoyaltyManager has key {
        id: UID,
        total_royalties_distributed: u64,
        dataset_configs: Table<vector<u8>, RoyaltyConfig>,
    }

    /// Configuration for dataset royalties
    public struct RoyaltyConfig has store {
        dataset_id: vector<u8>,
        creator: address,
        curator: address,
        creator_percent: u8, // 40
        curator_percent: u8, // 40
        platform_percent: u8, // 20
        active: bool,
    }

    /// Accumulated royalties per recipient
    public struct RoyaltyAccumulator has key {
        id: UID,
        dataset_id: vector<u8>,
        creator: address,
        curator: address,
        creator_accumulated: u64,
        curator_accumulated: u64,
        platform_accumulated: u64,
    }

    // ============= EVENTS =============

    public struct RoyaltyConfigCreatedEvent has copy, drop {
        dataset_id: vector<u8>,
        creator: address,
        curator: address,
        timestamp: u64,
    }

    public struct RoyaltyDistributedEvent has copy, drop {
        dataset_id: vector<u8>,
        creator_amount: u64,
        curator_amount: u64,
        platform_amount: u64,
        timestamp: u64,
    }

    public struct RoyaltyWithdrawnEvent has copy, drop {
        recipient: address,
        amount: u64,
        timestamp: u64,
    }

    // ============= INITIALIZATION =============

    fun init(ctx: &mut TxContext) {
        let manager = RoyaltyManager {
            id: object::new(ctx),
            total_royalties_distributed: 0,
            dataset_configs: table::new(ctx),
        };
        transfer::share_object(manager);
    }

    // ============= ROYALTY SETUP =============

    /// Create royalty configuration for dataset
    public entry fun create_royalty_config(
        manager: &mut RoyaltyManager,
        dataset_id: vector<u8>,
        creator: address,
        curator: address,
        ctx: &mut TxContext
    ) {
        assert!(vector::length(&dataset_id) > 0, E_INVALID_AMOUNT);

        let config = RoyaltyConfig {
            dataset_id: copy dataset_id,
            creator,
            curator,
            creator_percent: 40,
            curator_percent: 40,
            platform_percent: 20,
            active: true,
        };

        table::add(&mut manager.dataset_configs, copy dataset_id, config);

        let accumulator = RoyaltyAccumulator {
            id: object::new(ctx),
            dataset_id,
            creator,
            curator,
            creator_accumulated: 0,
            curator_accumulated: 0,
            platform_accumulated: 0,
        };

        event::emit(RoyaltyConfigCreatedEvent {
            dataset_id: copy dataset_id,
            creator,
            curator,
            timestamp: tx_context::epoch(ctx),
        });

        transfer::share_object(accumulator);
    }

    // ============= ROYALTY DISTRIBUTION =============

    /// Distribute royalties from model usage revenue
    public entry fun distribute_royalties(
        manager: &RoyaltyManager,
        accumulator: &mut RoyaltyAccumulator,
        revenue_coin: Coin<sui::sui::SUI>,
        ctx: &mut TxContext
    ) {
        let revenue_amount = coin::value(&revenue_coin);
        assert!(revenue_amount > 0, E_INVALID_AMOUNT);

        // Get config
        let config = table::borrow(
            &manager.dataset_configs,
            copy accumulator.dataset_id
        );

        assert!(config.active, E_UNAUTHORIZED);

        // Calculate splits (5% royalty pool)
        let royalty_pool = (revenue_amount * 5) / 100;
        let creator_royalty = (royalty_pool * 50) / 100;
        let curator_royalty = royalty_pool - creator_royalty;

        // Update accumulator
        accumulator.creator_accumulated = accumulator.creator_accumulated + creator_royalty;
        accumulator.curator_accumulated = accumulator.curator_accumulated + curator_royalty;
        accumulator.platform_accumulated = accumulator.platform_accumulated + (revenue_amount - royalty_pool);

        event::emit(RoyaltyDistributedEvent {
            dataset_id: copy accumulator.dataset_id,
            creator_amount: creator_royalty,
            curator_amount: curator_royalty,
            platform_amount: revenue_amount - royalty_pool,
            timestamp: tx_context::epoch(ctx),
        });

        // Destroy coin (burned for now, can be improved)
        coin::destroy_zero(revenue_coin);
    }

    // ============= WITHDRAWAL =============

    /// Withdraw accumulated royalties
    public entry fun withdraw_royalties(
        accumulator: &mut RoyaltyAccumulator,
        recipient: address,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let requester = tx_context::sender(ctx);

        // Verify requester is creator or curator
        assert!(
            requester == accumulator.creator || requester == accumulator.curator,
            E_UNAUTHORIZED
        );

        // Check available balance
        let available = if (requester == accumulator.creator) {
            accumulator.creator_accumulated
        } else {
            accumulator.curator_accumulated
        };

        assert!(amount <= available, E_INSUFFICIENT_BALANCE);

        // Update accumulator
        if (requester == accumulator.creator) {
            accumulator.creator_accumulated = accumulator.creator_accumulated - amount;
        } else {
            accumulator.curator_accumulated = accumulator.curator_accumulated - amount;
        };

        event::emit(RoyaltyWithdrawnEvent {
            recipient,
            amount,
            timestamp: tx_context::epoch(ctx),
        });
    }

    // ============= QUERY FUNCTIONS =============

    public fun get_config(
        manager: &RoyaltyManager,
        dataset_id: vector<u8>
    ): (address, address, u8, u8, u8) {
        let config = table::borrow(&manager.dataset_configs, dataset_id);
        (config.creator, config.curator, config.creator_percent, config.curator_percent, config.platform_percent)
    }

    public fun get_accumulated_royalties(
        accumulator: &RoyaltyAccumulator
    ): (u64, u64, u64) {
        (accumulator.creator_accumulated, accumulator.curator_accumulated, accumulator.platform_accumulated)
    }
}
