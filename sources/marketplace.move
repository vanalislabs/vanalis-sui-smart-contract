
module vanalis::marketplace {
    use sui::event;
    use sui::coin::{Self,Coin};
    use sui::balance::{Self, Balance};
    use sui::object;
    use sui::object::ID;
    use sui::table::{Self, Table};
    use std::string;
    use std::string::String;
    use sui::clock::Clock;

    use vanalis::project;

    const E_PROJECT_NOT_COMPLETED: u64 = 2001;
    const E_ALREADY_PURCHASED: u64 = 2002;
    const E_INVALID_AMOUNT: u64 = 2003;

    public struct Marketplace has key {
        id: UID,
        total_listings: u64,
        total_sales_amount: u64,
        total_sales_count: u64,
    }

    public struct MarketplaceListing has key, store {
        id: UID,
        project_id: ID,
        price: u64,
        dataset_collection_blob_id: String,
        dataset_collection_public_key: String,
        last_sale_epoch_timestamp: u64,
        total_sales_amount: u64,
        total_sales_count: u64,
        sales: Table<address, Sale>,
        curator: address,
        created_at: u64,
        updated_at: u64,
    }

    public struct Sale has key, store {
        id: UID,
        listing_id: ID,
        buyer: address,
        paid_amount: u64,
        bought_at: u64,
    }

    // EVENTS
    public struct ListingCreatedEvent has copy, drop {
        id: ID,
        project_id: ID,
        price: u64,
        dataset_collection_blob_id: String,
        dataset_collection_public_key: String,
        last_sale_epoch_timestamp: u64,
        created_at: u64,
    }

    public struct ListingUpdatedEvent has copy, drop {
        id: ID,
        price: u64,
        last_sale_epoch_timestamp: u64,
        updated_at: u64,
    }

    public struct ListingPurchasedEvent has copy, drop {
        sale_id: ID,
        listing_id: ID,
        project_id: ID,
        buyer: address,
        paid_amount: u64,
        dataset_collection_blob_id: String,
        dataset_collection_public_key: String,
        bought_at: u64,
    }

    fun init(ctx: &mut TxContext) {
        let marketplace = Marketplace {
            id: object::new(ctx),
            total_listings: 0,
            total_sales_amount: 0,
            total_sales_count: 0,
        };

        transfer::share_object(marketplace);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }

    /// Create marketplace listing for published dataset
    public fun create_listing(
        marketplace: &mut Marketplace,
        project: &mut project::Project,
        price: u64,
        dataset_collection_blob_id: String,
        dataset_collection_public_key: String,
        last_sale_epoch_timestamp: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let project_status = project::get_status(project);
        let total_listings = marketplace.total_listings + 1;
        
        assert!(
            project_status == project::status_completed() 
            || project_status == project::status_closed(), 
            E_PROJECT_NOT_COMPLETED
        );
        assert!(project::get_has_dataset(project), E_INVALID_AMOUNT);
        assert!(price > 0, E_INVALID_AMOUNT);
        assert!(!string::is_empty(&dataset_collection_blob_id), E_INVALID_AMOUNT);
        assert!(!string::is_empty(&dataset_collection_public_key), E_INVALID_AMOUNT);

        let curator = tx_context::sender(ctx);

        let listing = MarketplaceListing {
            id: object::new(ctx),
            project_id: object::id(project),
            price: price,
            dataset_collection_blob_id: dataset_collection_blob_id,
            dataset_collection_public_key: dataset_collection_public_key,
            last_sale_epoch_timestamp,
            total_sales_amount: 0,
            total_sales_count: 0,
            sales: table::new(ctx),
            curator,
            created_at: clock.timestamp_ms(),
            updated_at: clock.timestamp_ms(),
        };

        event::emit(ListingCreatedEvent {
            id: object::id(&listing),
            project_id: object::id(project),
            price: price,
            dataset_collection_blob_id: dataset_collection_blob_id,
            dataset_collection_public_key: dataset_collection_public_key,
            last_sale_epoch_timestamp: last_sale_epoch_timestamp,
            created_at: clock.timestamp_ms(),
        });

        project::set_is_listed(project, true);
        marketplace.total_listings = total_listings;

        transfer::share_object(listing);
    }

    public fun update_listing(
        listing: &mut MarketplaceListing,
        last_sale_epoch_timestamp: u64,
        price: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(price > 0, E_INVALID_AMOUNT);
        assert!(last_sale_epoch_timestamp > listing.last_sale_epoch_timestamp, E_INVALID_AMOUNT);
        assert!(tx_context::sender(ctx) == listing.curator, E_INVALID_AMOUNT);

        listing.price = price;
        listing.last_sale_epoch_timestamp = last_sale_epoch_timestamp;
        listing.updated_at = clock.timestamp_ms();
        event::emit(ListingUpdatedEvent {
            id: object::id(listing),
            price,
            last_sale_epoch_timestamp,
            updated_at: clock.timestamp_ms(),
        })
    }

    public fun purchase(
        marketplace: &mut Marketplace,
        platform_treasury: &mut vanalis::treasury::PlatformTreasury,
        project: &project::Project,
        listing: &mut MarketplaceListing,
        mut payment_coin: Coin<sui::sui::SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let coin_value = coin::value(&payment_coin);
        assert!(coin_value >= listing.price, E_INVALID_AMOUNT);

        let buyer = tx_context::sender(ctx);
        assert!(!table::contains(&listing.sales, buyer), E_ALREADY_PURCHASED);

        let correct_coin = coin::split(&mut payment_coin, listing.price, ctx);
        let bought_at = clock.timestamp_ms();

        let sale = Sale {
            id: object::new(ctx),
            listing_id: object::id(listing),
            buyer,
            paid_amount: listing.price,
            bought_at,
        };
        let sale_id = object::id(&sale);

        table::add(&mut listing.sales, tx_context::sender(ctx), sale);

        event::emit(ListingPurchasedEvent {
            sale_id,
            listing_id: object::id(listing),
            project_id: listing.project_id,
            buyer,
            paid_amount: listing.price,
            dataset_collection_blob_id: listing.dataset_collection_blob_id,
            dataset_collection_public_key: listing.dataset_collection_public_key,
            bought_at,
        });

        // Update Marketplace Stats
        marketplace.total_sales_amount = marketplace.total_sales_amount + listing.price;
        marketplace.total_sales_count = marketplace.total_sales_count + 1;

        // Update listing total sales amount and count
        listing.total_sales_amount = listing.total_sales_amount + listing.price;
        listing.total_sales_count = listing.total_sales_count + 1;
        
        // Send back the remaining coin to the buyer
        transfer::public_transfer(payment_coin, buyer);

        // Distribute earnings to the curator, platform, and contributors
        let curator_address = listing.curator;
        vanalis::treasury::distribute_earnings_from_sale(platform_treasury, project, curator_address, correct_coin, ctx);
    }

    public fun get_listing_curator(listing: &MarketplaceListing): address {
        listing.curator
    }
}