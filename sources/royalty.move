module vanalis::royalty {
    use sui::event;

    // CONSTANTS
    const E_INVALID_AMOUNT: u64 = 1;
    const E_INSUFFICIENT_BALANCE: u64 = 2;
    const E_UNAUTHORIZED: u64 = 3;

    // ============= STRUCTS =============

    /// Global royalty tracking
    public struct RoyaltyManager has key {
        id: object::UID,
        total_royalties_distributed: u64,
        dataset_configs: sui::table::Table<vector<u8>, RoyaltyConfig>,
    }

    /// Simplified royalty configuration - only essential data on-chain
    public struct RoyaltyConfig has store {
        dataset_hash: vector<u8>, // Hash of off-chain dataset metadata
        creator: address,
        curator: address,
        creator_percent: u8, // 40
        curator_percent: u8, // 40
        platform_percent: u8, // 20
        active: bool,
    }

    /// Accumulated royalties per recipient
    public struct RoyaltyAccumulator has key {
        id: object::UID,
        dataset_hash: vector<u8>,
        creator: address,
        curator: address,
        creator_accumulated: u64,
        curator_accumulated: u64,
        platform_accumulated: u64,
        treasury: sui::balance::Balance<sui::sui::SUI>,
    }

    // ============= EVENTS =============

    public struct RoyaltyConfigCreatedEvent has copy, drop {
        dataset_hash: vector<u8>,
        creator: address,
        curator: address,
        timestamp: u64,
    }

    public struct RoyaltyDistributedEvent has copy, drop {
        dataset_hash: vector<u8>,
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

    fun init(ctx: &mut tx_context::TxContext) {
        let manager = RoyaltyManager {
            id: object::new(ctx),
            total_royalties_distributed: 0,
            dataset_configs: sui::table::new(ctx),
        };
        transfer::share_object(manager);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut tx_context::TxContext) {
        init(ctx);
    }

    // ============= ROYALTY SETUP =============

    /// Create royalty configuration for dataset
    public fun create_royalty_config(
        manager: &mut RoyaltyManager,
        dataset_hash: vector<u8>,
        creator: address,
        curator: address,
        ctx: &mut tx_context::TxContext
    ) {
        assert!(vector::length(&dataset_hash) > 0, E_INVALID_AMOUNT);

        let config = RoyaltyConfig {
            dataset_hash: copy dataset_hash,
            creator,
            curator,
            creator_percent: 40,
            curator_percent: 40,
            platform_percent: 20,
            active: true,
        };

        sui::table::add(&mut manager.dataset_configs, copy dataset_hash, config);

        let accumulator = RoyaltyAccumulator {
            id: object::new(ctx),
            dataset_hash,
            creator,
            curator,
            creator_accumulated: 0,
            curator_accumulated: 0,
            platform_accumulated: 0,
            treasury: sui::balance::zero(),
        };

        event::emit(RoyaltyConfigCreatedEvent {
            dataset_hash: copy dataset_hash,
            creator,
            curator,
            timestamp: tx_context::epoch(ctx),
        });

        transfer::share_object(accumulator);
    }

    // ============= ROYALTY DISTRIBUTION =============

    /// Distribute royalties from model usage revenue
    public fun distribute_royalties(
        manager: &RoyaltyManager,
        accumulator: &mut RoyaltyAccumulator,
        platform_treasury: &mut sui::balance::Balance<sui::sui::SUI>,
        mut revenue_coin: sui::coin::Coin<sui::sui::SUI>,
        ctx: &mut tx_context::TxContext
    ) {
        let revenue_amount = sui::coin::value(&revenue_coin);
        assert!(revenue_amount > 0, E_INVALID_AMOUNT);

        // Get config
        let config = sui::table::borrow(
            &manager.dataset_configs,
            copy accumulator.dataset_hash
        );

        assert!(config.active, E_UNAUTHORIZED);

        // Calculate splits (50/40/10)
        let curator_share = (revenue_amount * 50) / 100;
        let creator_share = (revenue_amount * 40) / 100;
        let platform_share = revenue_amount - curator_share - creator_share;

        // Update accumulator ledgers
        accumulator.creator_accumulated = accumulator.creator_accumulated + creator_share;
        accumulator.curator_accumulated = accumulator.curator_accumulated + curator_share;
        accumulator.platform_accumulated = accumulator.platform_accumulated + platform_share;

        // Move coins into accumulator treasury
        let curator_coin = sui::coin::split(&mut revenue_coin, curator_share, ctx);
        let creator_coin = sui::coin::split(&mut revenue_coin, creator_share, ctx);
        sui::coin::put(&mut accumulator.treasury, curator_coin);
        sui::coin::put(&mut accumulator.treasury, creator_coin);

        // Platform share to treasury
        let platform_coin = revenue_coin;
        sui::coin::put(platform_treasury, platform_coin);

        event::emit(RoyaltyDistributedEvent {
            dataset_hash: copy accumulator.dataset_hash,
            creator_amount: creator_share,
            curator_amount: curator_share,
            platform_amount: platform_share,
            timestamp: tx_context::epoch(ctx),
        });
    }

    // ============= WITHDRAWAL =============

    /// Withdraw accumulated royalties with coin transfer
    public fun withdraw_royalties_with_coin(
        accumulator: &mut RoyaltyAccumulator,
        amount: u64,
        ctx: &mut tx_context::TxContext
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

        // Transfer coins
        let withdraw_coin = sui::coin::take(&mut accumulator.treasury, amount, ctx);
        transfer::public_transfer(withdraw_coin, requester);

        event::emit(RoyaltyWithdrawnEvent {
            recipient: requester,
            amount,
            timestamp: tx_context::epoch(ctx),
        });
    }

    // ============= QUERY FUNCTIONS =============

    public fun get_config(
        manager: &RoyaltyManager,
        dataset_hash: vector<u8>
    ): (address, address, u8, u8, u8) {
        let config = sui::table::borrow(&manager.dataset_configs, dataset_hash);
        (config.creator, config.curator, config.creator_percent, config.curator_percent, config.platform_percent)
    }

    public fun get_accumulated_royalties(
        accumulator: &RoyaltyAccumulator
    ): (u64, u64, u64) {
        (accumulator.creator_accumulated, accumulator.curator_accumulated, accumulator.platform_accumulated)
    }

    public fun creator_balance(accumulator: &RoyaltyAccumulator): u64 {
        accumulator.creator_accumulated
    }

    public fun curator_balance(accumulator: &RoyaltyAccumulator): u64 {
        accumulator.curator_accumulated
    }

    public fun get_dataset_hash(
        accumulator: &RoyaltyAccumulator
    ): vector<u8> {
        accumulator.dataset_hash
    }

    public fun get_creator(
        accumulator: &RoyaltyAccumulator
    ): address {
        accumulator.creator
    }

    public fun get_curator(
        accumulator: &RoyaltyAccumulator
    ): address {
        accumulator.curator
    }

    public fun is_config_active(
        manager: &RoyaltyManager,
        dataset_hash: vector<u8>
    ): bool {
        let config = sui::table::borrow(&manager.dataset_configs, dataset_hash);
        config.active
    }

    /// Deactivate royalty configuration
    public fun deactivate_royalty_config(
        manager: &mut RoyaltyManager,
        dataset_hash: vector<u8>,
        ctx: &mut tx_context::TxContext
    ) {
        let config = sui::table::borrow_mut(&mut manager.dataset_configs, dataset_hash);
        
        // Only creator or curator can deactivate
        assert!(
            tx_context::sender(ctx) == config.creator || tx_context::sender(ctx) == config.curator,
            E_UNAUTHORIZED
        );
        
        config.active = false;
    }
}
