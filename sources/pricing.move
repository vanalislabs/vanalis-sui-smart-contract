module vanalis::pricing {
    use sui::table::{Self, Table};
    use sui::event;

    const E_NOT_ADMIN: u64 = 1;
    const E_INVALID_PRICE: u64 = 2;
    const E_PRICE_NOT_FOUND: u64 = 3;

    public struct PriceOracle has key {
        id: UID,
        admin: address,
        prices: Table<vector<u8>, u64>,
    }

    public struct PriceUpdatedEvent has copy, drop {
        dataset_hash: vector<u8>,
        price: u64,
        timestamp: u64,
    }

    fun init(ctx: &mut TxContext) {
        let oracle = PriceOracle {
            id: object::new(ctx),
            admin: tx_context::sender(ctx),
            prices: table::new(ctx),
        };
        transfer::share_object(oracle);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    public fun set_price(
        oracle: &mut PriceOracle,
        dataset_hash: vector<u8>,
        price: u64,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == oracle.admin, E_NOT_ADMIN);
        assert!(price > 0, E_INVALID_PRICE);

        if (table::contains(&oracle.prices, copy dataset_hash)) {
            let entry = table::borrow_mut(&mut oracle.prices, copy dataset_hash);
            *entry = price;
        } else {
            table::add(&mut oracle.prices, copy dataset_hash, price);
        };

        event::emit(PriceUpdatedEvent {
            dataset_hash,
            price,
            timestamp: tx_context::epoch(ctx),
        });
    }

    public fun get_price(
        oracle: &PriceOracle,
        dataset_hash: vector<u8>
    ): u64 {
        let price_ref = table::borrow(&oracle.prices, dataset_hash);
        *price_ref
    }

    public fun require_price(
        oracle: &PriceOracle,
        dataset_hash: vector<u8>
    ): u64 {
        if (table::contains(&oracle.prices, copy dataset_hash)) {
            let price_ref = table::borrow(&oracle.prices, dataset_hash);
            *price_ref
        } else {
            abort E_PRICE_NOT_FOUND
        }
    }
}
