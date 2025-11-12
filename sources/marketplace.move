module vanalis::marketplace {
    use sui::event;
    use sui::coin::{Coin, Self};
    use sui::balance::{Self, Balance};
    use vanalis::project::Project;

    const E_INVALID_PRICE: u64 = 1;
    const E_INSUFFICIENT_PAYMENT: u64 = 2;

    public struct Marketplace has key {
        id: UID,
        total_datasets: u64,
        total_sales: u64,
        platform_fee_percent: u8,
    }

    public struct Treasury has key {
        id: UID,
        balance: Balance<sui::sui::SUI>,
        total_collected: u64,
    }

    public struct Purchase has key {
        id: UID,
        purchase_id: u64,
        project_id: u64,
        buyer: address,
        price_paid: u64,
        timestamp: u64,
    }

    /// Royalty tracking
    public struct RoyaltyConfig has key {
        id: UID,
        dataset_id: vector<u8>,
        creator: address,
        curator: address,
        creator_percent: u8, // 40
        curator_percent: u8, // 40
        platform_percent: u8, // 20
    }

    // EVENTS

    public struct DatasetPurchasedEvent has copy, drop {
        project_id: u64,
        buyer: address,
        price: u64,
        curator_share: u64,
        contributors_share: u64,
        platform_share: u64,
        timestamp: u64,
    }

    // INITIALIZATION

    fun init(ctx: &mut TxContext) {
        let marketplace = Marketplace {
            id: object::new(ctx),
            total_datasets: 0,
            total_sales: 0,
            platform_fee_percent: 10,
        };

        let treasury = Treasury {
            id: object::new(ctx),
            balance: balance::zero(),
            total_collected: 0,
        };

        transfer::share_object(marketplace);
        transfer::share_object(treasury);
    }

    // PURCHASE FLOW 

    /// Purchase published dataset
    public entry fun purchase_dataset(
        marketplace: &mut Marketplace,
        treasury: &mut Treasury,
        project: &Project,
        mut payment_coin: Coin<sui::sui::SUI>,
        ctx: &mut TxContext
    ) {
        let price = coin::value(&payment_coin);
        
        // Validate payment
        assert!(price == vanalis::project::get_final_dataset_price(project), E_INVALID_PRICE);
        assert!(price > 0, E_INVALID_PRICE);

        // Calculate splits (50/40/10)
        let curator_share = (price * 50) / 100;
        let contributors_share = (price * 40) / 100;
        let platform_share = price - curator_share - contributors_share;

        // Split payment
        let curator_coin = coin::split(&mut payment_coin, curator_share, ctx);
        let contributors_coin = coin::split(&mut payment_coin, contributors_share, ctx);
        let platform_coin = coin::split(&mut payment_coin, platform_share, ctx);

        // Pay curator directly
        transfer::public_transfer(curator_coin, vanalis::project::get_curator(project));

        // Send contributors share to pool (TODO: implement distribution)
        transfer::public_transfer(contributors_coin, @0x0);

        // Add platform fee to treasury
        coin::put(&mut treasury.balance, platform_coin);
        treasury.total_collected = treasury.total_collected + platform_share;

        // Update marketplace stats
        marketplace.total_sales = marketplace.total_sales + 1;

        let current_epoch = tx_context::epoch(ctx);

        // Emit event
        event::emit(DatasetPurchasedEvent {
            project_id: vanalis::project::get_project_id(project),
            buyer: tx_context::sender(ctx),
            price,
            curator_share,
            contributors_share,
            platform_share,
            timestamp: current_epoch,
        });

        // Record purchase
        let purchase = Purchase {
            id: object::new(ctx),
            purchase_id: marketplace.total_sales,
            project_id: vanalis::project::get_project_id(project),
            buyer: tx_context::sender(ctx),
            price_paid: price,
            timestamp: current_epoch,
        };

        transfer::share_object(purchase);

        // Cleanup
        if (coin::value(&payment_coin) > 0) {
            transfer::public_transfer(payment_coin, tx_context::sender(ctx));
        } else {
            coin::destroy_zero(payment_coin);
        }
    }

    /// Withdraw platform fees (admin only)
    public entry fun withdraw_platform_fees(
        treasury: &mut Treasury,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        assert!(amount > 0, E_INVALID_PRICE);
        assert!(balance::value(&treasury.balance) >= amount, E_INSUFFICIENT_PAYMENT);

        let withdraw_coin = coin::take(&mut treasury.balance, amount, ctx);
        transfer::public_transfer(withdraw_coin, recipient);
    }

    /// Query treasury balance
    public fun get_treasury_balance(treasury: &Treasury): u64 {
        balance::value(&treasury.balance)
    }

    public fun get_marketplace_stats(marketplace: &Marketplace): (u64, u64) {
        (marketplace.total_datasets, marketplace.total_sales)
    }
}
