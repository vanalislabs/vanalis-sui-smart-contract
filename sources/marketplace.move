
module vanalis::marketplace {
    use sui::event;
    use sui::coin::{Coin, Self};
    use sui::balance::{Self, Balance};
    use sui::object;
    use sui::object::ID;
    use vanalis::project;

    const E_INVALID_PRICE: u64 = 1;
    const E_INSUFFICIENT_PAYMENT: u64 = 2;
    const E_DATASET_ALREADY_LISTED: u64 = 3;
    const E_LISTING_INACTIVE: u64 = 4;
    const E_DATASET_MISMATCH: u64 = 5;
    const E_NOT_DATA_OWNER: u64 = 6;

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
        project_id: ID,
        buyer: address,
        price_paid: u64,
        timestamp: u64,
    }

    public struct MarketplaceListing has key {
        id: UID,
        project_id: ID,
        dataset_hash: vector<u8>,
        dataset_object: address,
        price_sui: u64,
        curator: address,
        seller: address,
        dataset_blob_id: vector<u8>,
        // metadata_hash: vector<u8>,
        active: bool,
        created_at: u64,
        updated_at: u64,
    }

    public struct Dataset has key, store {
        id: UID,
        project_id: ID,
        curator: address,
        creator: address,
        price_usdc: u64,
        dataset_hash: vector<u8>,
        dataset_blob_id: vector<u8>,
        listed: bool,
        created_at: u64,
        last_sale_epoch: u64,
    }

    public struct DatasetAccessToken has key, store {
        id: UID,
        dataset_hash: vector<u8>,
        project_id: ID,
        buyer: address,
        dataset_blob_id: vector<u8>,
        // metadata_hash: vector<u8>,
        issued_at: u64,
    }

    // EVENTS

    public struct DatasetPurchasedEvent has copy, drop {
        project_id: ID,
        dataset_hash: vector<u8>,
        dataset_object: address,
        buyer: address,
        price: u64,
        curator_share: u64,
        creator_share: u64,
        platform_share: u64,
        timestamp: u64,
    }

    public struct ListingCreatedEvent has copy, drop {
        project_id: ID,
        dataset_hash: vector<u8>,
        dataset_object: address,
        price_sui: u64,
        curator: address,
        seller: address,
        timestamp: u64,
    }

fun init(ctx: &mut TxContext) {
    let marketplace = Marketplace {
        id: object::new(ctx),
        total_datasets: 0,
        total_sales: 0,
        platform_fee_percent: 5,
    };

    let treasury = Treasury {
        id: object::new(ctx),
        balance: balance::zero(),
        total_collected: 0,
    };

    transfer::share_object(marketplace);
    transfer::share_object(treasury);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

    /// Create marketplace listing for published dataset
    public fun create_listing(
        marketplace: &mut Marketplace,
        oracle: &pricing::PriceOracle,
        dataset: &mut Dataset,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert_dataset_owner(dataset, sender);
        assert!(!is_dataset_listed(dataset), E_DATASET_ALREADY_LISTED);

        let dataset_hash = get_dataset_hash(dataset);
        let price_sui = pricing::require_price(oracle, copy dataset_hash);
        assert!(price_sui > 0, E_INVALID_PRICE);

        // let (full_blob, preview_blob, metadata_hash) = get_dataset_blob_refs(dataset);
        let dataset_blob_id = get_dataset_blob_ref(dataset);
        let dataset_address = get_dataset_object_address(dataset);

        mark_dataset_listed(dataset, true);

        let listing = MarketplaceListing {
            id: object::new(ctx),
            project_id: get_dataset_project(dataset),
            dataset_hash: copy dataset_hash,
            dataset_object: dataset_address,
            price_sui,
            price_usdc: get_dataset_price_usdc(dataset),
            curator: get_dataset_curator(dataset),
            seller: sender,
            dataset_blob_id: copy dataset_blob_id,
            // metadata_hash,
            active: true,
            created_at: tx_context::epoch(ctx),
            updated_at: tx_context::epoch(ctx),
        };

        marketplace.total_datasets = marketplace.total_datasets + 1;

        event::emit(ListingCreatedEvent {
            project_id: listing.project_id,
            dataset_hash,
            dataset_object: dataset_address,
            price_sui,
            curator: listing.curator,
            seller: sender,
            timestamp: tx_context::epoch(ctx),
        });

        transfer::share_object(listing);
    }

    // PURCHASE FLOW 

    /// Purchase published dataset
    public fun purchase_dataset(
        marketplace: &mut Marketplace,
        treasury: &mut Treasury,
        royalty_manager: &royalty::RoyaltyManager,
        accumulator: &mut royalty::RoyaltyAccumulator,
        dataset: &mut Dataset,
        listing: &mut MarketplaceListing,
        payment_coin: Coin<sui::sui::SUI>,
        ctx: &mut TxContext
    ) {
        assert!(listing.active, E_LISTING_INACTIVE);
        assert!(is_dataset_listed(dataset), E_LISTING_INACTIVE);

        let listing_hash = copy listing.dataset_hash;
        assert!(listing_hash == get_dataset_hash(dataset), E_DATASET_MISMATCH);
        assert!(listing_hash == royalty::get_dataset_hash(accumulator), E_DATASET_MISMATCH);

        let price = listing.price_sui;
        assert!(price > 0, E_INVALID_PRICE);

        let total_payment = coin::value(&payment_coin);
        assert!(total_payment >= price, E_INVALID_PRICE);

        let curator_share = (price * 50) / 100;
        let creator_share = (price * 45) / 100;
        let platform_share = price - curator_share - creator_share;

        let mut sale_coin = payment_coin;
        if (total_payment > price) {
            let change_amount = total_payment - price;
            let change_coin = coin::split(&mut sale_coin, change_amount, ctx);
            transfer::public_transfer(change_coin, tx_context::sender(ctx));
        };

        treasury.total_collected = treasury.total_collected + platform_share;
        marketplace.total_sales = marketplace.total_sales + 1;

        listing.active = false;
        listing.updated_at = tx_context::epoch(ctx);
        mark_dataset_listed(dataset, false);
        touch_dataset_sale(dataset, listing.updated_at);

        let current_epoch = listing.updated_at;

        let token = DatasetAccessToken {
            id: object::new(ctx),
            dataset_hash: listing_hash,
            project_id: listing.project_id,
            buyer: tx_context::sender(ctx),
            dataset_blob_id: listing.dataset_blob_id,
            // metadata_hash: listing.metadata_hash,
            issued_at: current_epoch,
        };

        transfer::public_transfer(token, tx_context::sender(ctx));

        event::emit(DatasetPurchasedEvent {
            project_id: listing.project_id,
            dataset_hash: listing_hash,
            dataset_object: listing.dataset_object,
            buyer: tx_context::sender(ctx),
            price,
            curator_share,
            creator_share,
            platform_share,
            timestamp: current_epoch,
        });

        let purchase = Purchase {
            id: object::new(ctx),
            purchase_id: marketplace.total_sales,
            project_id: listing.project_id,
            buyer: tx_context::sender(ctx),
            price_paid: price,
            timestamp: current_epoch,
        };

        transfer::share_object(purchase);
    }

    /// Withdraw platform fees (admin only)
    public fun withdraw_platform_fees(
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

    public fun get_listing_info(listing: &MarketplaceListing): (ID, vector<u8>, address, u64, bool) {
        (listing.project_id, listing.dataset_hash, listing.dataset_object, listing.price_sui, listing.active)
    }

    public fun get_treasury_collected(treasury: &Treasury): u64 {
        treasury.total_collected
    }

    public fun is_listing_active(listing: &MarketplaceListing): bool {
        listing.active
    }

    public fun access_token_project_id(token: &DatasetAccessToken): ID {
        token.project_id
    }

    public fun access_token_matches_hash(
        token: &DatasetAccessToken,
        expected: vector<u8>
    ): bool {
        token.dataset_hash == expected
    }

    public fun assert_dataset_owner(dataset: &Dataset, signer: address) {
        assert!(dataset.creator == signer, E_NOT_DATA_OWNER);
    }

    public fun is_dataset_listed(dataset: &Dataset): bool {
        dataset.listed
    }

    public fun mark_dataset_listed(dataset: &mut Dataset, listed: bool) {
        dataset.listed = listed;
    }

    public fun get_dataset_hash(dataset: &Dataset): vector<u8> {
        copy dataset.dataset_hash
    }

    public fun get_dataset_price_usdc(dataset: &Dataset): u64 {
        dataset.price_usdc
    }

    public fun get_dataset_project(dataset: &Dataset): ID {
        dataset.project_id
    }

    public fun get_dataset_curator(dataset: &Dataset): address {
        dataset.curator
    }

    public fun get_dataset_blob_ref(dataset: &Dataset): (vector<u8>) {
        (copy dataset.dataset_blob_id)
    }

    public fun touch_dataset_sale(dataset: &mut Dataset, epoch: u64) {
        dataset.last_sale_epoch = epoch;
    }

    public fun get_dataset_project_id(dataset: &Dataset): ID {
        dataset.project_id
    }

    public fun get_dataset_object_address(dataset: &Dataset): address {
        object::uid_to_address(&dataset.id)
    }
}
