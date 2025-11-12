module vanalis::reputation {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;

    // ============= STRUCTS =============

    public struct UserReputation has key {
        id: UID,
        user_address: address,
        role: u8, // 0=contributor, 1=curator, 2=collector
        
        total_score: u64,
        sales_count: u64,
        quality_score: u64, // 0-100 for curators
        
        created_at: u64,
        last_updated: u64,
    }

    // ============= EVENTS =============

    public struct ReputationUpdatedEvent has copy, drop {
        user: address,
        new_score: u64,
        reason: u8,
        timestamp: u64,
    }

    // ============= REPUTATION FUNCTIONS =============

    public entry fun create_profile(
        role: u8,
        ctx: &mut TxContext
    ) {
        let current_epoch = tx_context::epoch(ctx);

        let profile = UserReputation {
            id: object::new(ctx),
            user_address: tx_context::sender(ctx),
            role,
            total_score: 0,
            sales_count: 0,
            quality_score: 100, // start at 100
            created_at: current_epoch,
            last_updated: current_epoch,
        };

        transfer::share_object(profile);
    }

    public entry fun add_contributor_score(
        profile: &mut UserReputation,
        ctx: &mut TxContext
    ) {
        profile.total_score = profile.total_score + 5;
        profile.sales_count = profile.sales_count + 1;
        profile.last_updated = tx_context::epoch(ctx);

        event::emit(ReputationUpdatedEvent {
            user: profile.user_address,
            new_score: profile.total_score,
            reason: 0, // dataset_created
            timestamp: tx_context::epoch(ctx),
        });
    }

    public entry fun add_curator_score(
        profile: &mut UserReputation,
        quality_score: u64,
        ctx: &mut TxContext
    ) {
        // Average quality scores
        profile.quality_score = (profile.quality_score + quality_score) / 2;
        profile.total_score = profile.total_score + 10;
        profile.sales_count = profile.sales_count + 1;
        profile.last_updated = tx_context::epoch(ctx);

        event::emit(ReputationUpdatedEvent {
            user: profile.user_address,
            new_score: profile.total_score,
            reason: 1, // curation_approved
            timestamp: tx_context::epoch(ctx),
        });
    }

    public entry fun add_collector_score(
        profile: &mut UserReputation,
        ctx: &mut TxContext
    ) {
        profile.total_score = profile.total_score + 1;
        profile.sales_count = profile.sales_count + 1;
        profile.last_updated = tx_context::epoch(ctx);

        event::emit(ReputationUpdatedEvent {
            user: profile.user_address,
            new_score: profile.total_score,
            reason: 2, // purchase
            timestamp: tx_context::epoch(ctx),
        });
    }

    // ============= QUERY FUNCTIONS =============

    public fun get_score(profile: &UserReputation): u64 {
        profile.total_score
    }

    public fun get_quality_rating(profile: &UserReputation): u64 {
        profile.quality_score
    }

    public fun get_profile_info(profile: &UserReputation): (address, u8, u64, u64) {
        (profile.user_address, profile.role, profile.total_score, profile.sales_count)
    }
}
