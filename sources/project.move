
module vanalis::project {
    use sui::event;
    use sui::coin::{Coin, Self};
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use vanalis::royalty;

    const E_NOT_CREATOR: u64 = 1;
    const E_INVALID_STATUS: u64 = 2;
    const E_PROJECT_NOT_OPEN: u64 = 3;
    const E_INSUFFICIENT_REWARD_POOL: u64 = 4;
    const E_NOT_CURATOR: u64 = 5;
    const E_DEADLINE_PASSED: u64 = 6;
    const E_INVALID_AMOUNT: u64 = 7;
    const E_INVALID_ADDRESS: u64 = 8;
    const E_NOT_DATA_OWNER: u64 = 9;
    const E_DATASET_ALREADY_LISTED: u64 = 10;
    const E_DATASET_ALREADY_MINTED: u64 = 11;
    
    const STATUS_DRAFT: u8 = 0;
    const STATUS_OPEN: u8 = 1;
    const STATUS_COMPLETED: u8 = 2;
    const STATUS_PUBLISHED: u8 = 3;

    const SUBMISSION_PENDING: u8 = 0;
    const SUBMISSION_APPROVED: u8 = 1;
    const SUBMISSION_REJECTED: u8 = 2;

    public struct ProjectRegistry has key {
        id: UID,
        total_projects: u64,
        projects: Table<u64, address>, // project_id -> creator address
    }

    public struct Project has key {
        id: UID,
        project_id: u64,
        curator: address,
        
        data_type_hash: vector<u8>, // Hash of off-chain metadata
        criteria_hash: vector<u8>,  // Hash of quality criteria
        
        reward_pool: Balance<sui::sui::SUI>,
        total_reward_pool: u64,
        reward_per_submission: u64,
        rewards_paid_out: u64,
        
        target_submissions: u64,
        min_quality_score: u8,
        
        status: u8,
        submissions_count: u64,
        approved_count: u64,
        rejected_count: u64,
        
        // Final dataset reference
        final_dataset_hash: vector<u8>, // Hash of final dataset metadata
        final_dataset_price: u64,
        
        created_at: u64,
        deadline: u64,
    }

    public struct Submission has key {
        id: UID,
        submission_id: u64,
        project_id: u64,
        contributor: address,
        
        // Walrus blob references
        full_dataset_blob_id: vector<u8>,
        preview_blob_id: vector<u8>,
        total_items: u64,
        preview_items: u64,
        
        metadata_hash: vector<u8>, // Hash of off-chain metadata
        
        status: u8,
        quality_score: u8,
        
        reward_paid: u64,
        
        submitted_at: u64,
        reviewed_at: u64,
        dataset_minted: bool,
    }

    public struct ContributorStats has key {
        id: UID,
        project_id: u64,
        contributor: address,
        submissions_count: u64,
        approved_count: u64,
        total_earned: u64,
    }

    public struct Dataset has key, store {
        id: UID,
        project_id: u64,
        submission_id: u64,
        curator: address,
        creator: address,
        dataset_hash: vector<u8>,
        price_usdc: u64,
        full_dataset_blob_id: vector<u8>,
        preview_blob_id: vector<u8>,
        metadata_hash: vector<u8>,
        listed: bool,
        created_at: u64,
        last_sale_epoch: u64,
    }

    // EVENTS

    public struct ProjectCreatedEvent has copy, drop {
        project_id: u64,
        curator: address,
        data_type_hash: vector<u8>,
        criteria_hash: vector<u8>,
        reward_pool: u64,
        target_submissions: u64,
        timestamp: u64,
    }

    public struct SubmissionReceivedEvent has copy, drop {
        project_id: u64,
        submission_id: u64,
        contributor: address,
        metadata_hash: vector<u8>,
        total_items: u64,
        timestamp: u64,
    }

    public struct SubmissionReviewedEvent has copy, drop {
        submission_id: u64,
        approved: bool,
        quality_score: u8,
        reward_paid: u64,
        timestamp: u64,
    }

    public struct ProjectPublishedEvent has copy, drop {
        project_id: u64,
        final_dataset_hash: vector<u8>,
        price: u64,
        total_contributors: u64,
        timestamp: u64,
    }

    public struct DatasetMintedEvent has copy, drop {
        project_id: u64,
        submission_id: u64,
        dataset_hash: vector<u8>,
        creator: address,
        price_usdc: u64,
        timestamp: u64,
    }

    /// Init project registry
fun init(ctx: &mut TxContext) {
    let registry = ProjectRegistry {
        id: object::new(ctx),
        total_projects: 0,
        projects: table::new(ctx),
    };
    transfer::share_object(registry);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

    public fun create_project(
        registry: &mut ProjectRegistry,
        data_type_hash: vector<u8>,
        criteria_hash: vector<u8>,
        reward_coin: Coin<sui::sui::SUI>,
        reward_per_submission: u64,
        target_submissions: u64,
        min_quality_score: u8,
        deadline_epochs: u64,
        ctx: &mut TxContext
    ) {
        assert!(reward_per_submission > 0, E_INVALID_AMOUNT);
        assert!(target_submissions > 0, E_INVALID_AMOUNT);
        assert!(min_quality_score > 0, E_INVALID_AMOUNT);
        assert!(vector::length(&data_type_hash) > 0, E_INVALID_AMOUNT);
        assert!(vector::length(&criteria_hash) > 0, E_INVALID_AMOUNT);

        let reward_amount = coin::value(&reward_coin);
        let expected_total = reward_per_submission * target_submissions;
        
        assert!(reward_amount >= expected_total, E_INSUFFICIENT_REWARD_POOL);

        let project_id = registry.total_projects + 1;
        let creator = tx_context::sender(ctx);
        let current_epoch = tx_context::epoch(ctx);

        let project = Project {
            id: object::new(ctx),
            project_id,
            curator: creator,
            
            data_type_hash,
            criteria_hash,
            
            reward_pool: coin::into_balance(reward_coin),
            total_reward_pool: reward_amount,
            reward_per_submission,
            rewards_paid_out: 0,
            
            target_submissions,
            min_quality_score,
            
            status: STATUS_OPEN,
            submissions_count: 0,
            approved_count: 0,
            rejected_count: 0,
            
            final_dataset_hash: vector::empty(),
            final_dataset_price: 0,
            
            created_at: current_epoch,
            deadline: current_epoch + deadline_epochs,
        };

        registry.total_projects = project_id;
        table::add(&mut registry.projects, project_id, creator);

        event::emit(ProjectCreatedEvent {
            project_id,
            curator: creator,
            data_type_hash: project.data_type_hash,
            criteria_hash: project.criteria_hash,
            reward_pool: reward_amount,
            target_submissions,
            timestamp: current_epoch,
        });

        transfer::share_object(project);
    }

    public fun submit_data(
        project: &mut Project,
        full_dataset_blob_id: vector<u8>,
        preview_blob_id: vector<u8>,
        total_items: u64,
        preview_items: u64,
        metadata_hash: vector<u8>,
        ctx: &mut TxContext
    ) {
        assert!(project.status == STATUS_OPEN, E_PROJECT_NOT_OPEN);
        assert!(tx_context::epoch(ctx) < project.deadline, E_DEADLINE_PASSED);
        
        assert!(total_items > 0, E_INVALID_AMOUNT);
        assert!(preview_items > 0, E_INVALID_AMOUNT);
        assert!(preview_items <= total_items, E_INVALID_AMOUNT);
        assert!(vector::length(&metadata_hash) > 0, E_INVALID_AMOUNT);

        let submission_id = project.submissions_count + 1;
        let contributor = tx_context::sender(ctx);
        let current_epoch = tx_context::epoch(ctx);

        let submission = Submission {
            id: object::new(ctx),
            submission_id,
            project_id: project.project_id,
            contributor,
            
            full_dataset_blob_id,
            preview_blob_id,
            total_items,
            preview_items,
            
            metadata_hash,
            
            status: SUBMISSION_PENDING,
            quality_score: 0,
            
            reward_paid: 0,
            
            submitted_at: current_epoch,
            reviewed_at: 0,
            dataset_minted: false,
        };

        project.submissions_count = project.submissions_count + 1;

        event::emit(SubmissionReceivedEvent {
            project_id: project.project_id,
            submission_id,
            contributor,
            metadata_hash: copy metadata_hash,
            total_items,
            timestamp: current_epoch,
        });

        // Create contributor stats
        let stats = ContributorStats {
            id: object::new(ctx),
            project_id: project.project_id,
            contributor,
            submissions_count: 1,
            approved_count: 0,
            total_earned: 0,
        };

        transfer::share_object(submission);
        transfer::share_object(stats);
    }

    public fun review_submission(
        project: &mut Project,
        submission: &mut Submission,
        stats: &mut ContributorStats,
        approve: bool,
        quality_score: u8,
        ctx: &mut TxContext
    ) {
        assert!(project.curator == tx_context::sender(ctx), E_NOT_CURATOR);
        assert!(submission.status == SUBMISSION_PENDING, E_INVALID_STATUS);
        assert!(quality_score <= 100, E_INVALID_AMOUNT);

        let current_epoch = tx_context::epoch(ctx);
        submission.reviewed_at = current_epoch;
        submission.quality_score = quality_score;

        if (approve && quality_score >= project.min_quality_score) {
            // APPROVE: Transfer reward to contributor
            submission.status = SUBMISSION_APPROVED;
            
            let reward_coin = coin::take(
                &mut project.reward_pool,
                project.reward_per_submission,
                ctx
            );
            
            // Transfer to contributor
            transfer::public_transfer(reward_coin, submission.contributor);
            
            submission.reward_paid = project.reward_per_submission;
            project.rewards_paid_out = project.rewards_paid_out + project.reward_per_submission;
            project.approved_count = project.approved_count + 1;
            
            stats.approved_count = stats.approved_count + 1;
            stats.total_earned = stats.total_earned + project.reward_per_submission;

            event::emit(SubmissionReviewedEvent {
                submission_id: submission.submission_id,
                approved: true,
                quality_score,
                reward_paid: project.reward_per_submission,
                timestamp: current_epoch,
            });
        } else {
            // REJECT
            submission.status = SUBMISSION_REJECTED;
            project.rejected_count = project.rejected_count + 1;

            event::emit(SubmissionReviewedEvent {
                submission_id: submission.submission_id,
                approved: false,
                quality_score,
                reward_paid: 0,
                timestamp: current_epoch,
            });
        }
    }

    public fun mint_dataset_from_submission(
        project: &mut Project,
        submission: &mut Submission,
        royalty_manager: &mut royalty::RoyaltyManager,
        dataset_hash: vector<u8>,
        price_usdc: u64,
        ctx: &mut TxContext
    ) {
        assert!(project.curator == tx_context::sender(ctx), E_NOT_CURATOR);
        assert!(submission.project_id == project.project_id, E_INVALID_STATUS);
        assert!(submission.status == SUBMISSION_APPROVED, E_INVALID_STATUS);
        assert!(!submission.dataset_minted, E_DATASET_ALREADY_MINTED);
        assert!(vector::length(&dataset_hash) > 0, E_INVALID_AMOUNT);
        assert!(price_usdc > 0, E_INVALID_AMOUNT);

        submission.dataset_minted = true;
        project.status = STATUS_PUBLISHED;
        project.final_dataset_hash = copy dataset_hash;
        project.final_dataset_price = price_usdc;

        let current_epoch = tx_context::epoch(ctx);

        let dataset = Dataset {
            id: object::new(ctx),
            project_id: project.project_id,
            submission_id: submission.submission_id,
            curator: project.curator,
            creator: submission.contributor,
            dataset_hash: copy dataset_hash,
            price_usdc,
            full_dataset_blob_id: submission.full_dataset_blob_id,
            preview_blob_id: submission.preview_blob_id,
            metadata_hash: submission.metadata_hash,
            listed: false,
            created_at: current_epoch,
            last_sale_epoch: 0,
        };

        transfer::public_transfer(dataset, submission.contributor);

        royalty::create_royalty_config(
            royalty_manager,
            copy dataset_hash,
            submission.contributor,
            project.curator,
            ctx
        );

        event::emit(DatasetMintedEvent {
            project_id: project.project_id,
            submission_id: submission.submission_id,
            dataset_hash: copy dataset_hash,
            creator: submission.contributor,
            price_usdc,
            timestamp: current_epoch,
        });

        event::emit(ProjectPublishedEvent {
            project_id: project.project_id,
            final_dataset_hash: dataset_hash,
            price: price_usdc,
            total_contributors: project.approved_count,
            timestamp: current_epoch,
        });
    }

    /// Withdraw remaining reward for Curator
    public fun withdraw_remaining_rewards(
        project: &mut Project,
        ctx: &mut TxContext
    ) {
        assert!(project.curator == tx_context::sender(ctx), E_NOT_CURATOR);
        
        let remaining = balance::value(&project.reward_pool);
        if (remaining > 0) {
            let withdraw_coin = coin::take(&mut project.reward_pool, remaining, ctx);
            transfer::public_transfer(withdraw_coin, project.curator);
        }
    }

    // GET FUNCTION

    public fun get_project_status(project: &Project): u8 {
        project.status
    }

    public fun get_submission_status(submission: &Submission): u8 {
        submission.status
    }

    public fun get_project_info(project: &Project): (vector<u8>, vector<u8>, u64, u64, u64) {
        (
            project.data_type_hash,
            project.criteria_hash,
            project.submissions_count,
            project.approved_count,
            project.total_reward_pool,
        )
    }

    public fun get_contributor_stats(stats: &ContributorStats): (u64, u64, u64) {
        (stats.submissions_count, stats.approved_count, stats.total_earned)
    }

    public fun get_submission_info(submission: &Submission): (address, u64, u64, u8, vector<u8>) {
        (submission.contributor, submission.total_items, submission.reward_paid, submission.status, submission.metadata_hash)
    }

    public fun get_reward_pool_balance(project: &Project): u64 {
        balance::value(&project.reward_pool)
    }

    public fun get_project_id(project: &Project): u64 {
        project.project_id
    }

    public fun get_curator(project: &Project): address {
        project.curator
    }

    public fun get_final_dataset_price(project: &Project): u64 {
        project.final_dataset_price
    }

    public fun get_final_dataset_hash(project: &Project): vector<u8> {
        project.final_dataset_hash
    }

    public fun get_data_type_hash(project: &Project): vector<u8> {
        project.data_type_hash
    }

    public fun get_criteria_hash(project: &Project): vector<u8> {
        project.criteria_hash
    }

    public fun get_submission_metadata_hash(submission: &Submission): vector<u8> {
        submission.metadata_hash
    }

    public fun get_full_dataset_blob_id(submission: &Submission): vector<u8> {
        submission.full_dataset_blob_id
    }

    public fun get_preview_blob_id(submission: &Submission): vector<u8> {
        submission.preview_blob_id
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

    public fun get_dataset_project(dataset: &Dataset): u64 {
        dataset.project_id
    }

    public fun get_dataset_curator(dataset: &Dataset): address {
        dataset.curator
    }

    public fun get_dataset_blob_refs(dataset: &Dataset): (vector<u8>, vector<u8>, vector<u8>) {
        (copy dataset.full_dataset_blob_id, copy dataset.preview_blob_id, copy dataset.metadata_hash)
    }

    public fun touch_dataset_sale(dataset: &mut Dataset, epoch: u64) {
        dataset.last_sale_epoch = epoch;
    }

    public fun get_dataset_submission(dataset: &Dataset): u64 {
        dataset.submission_id
    }

    public fun get_dataset_object_address(dataset: &Dataset): address {
        object::uid_to_address(&dataset.id)
    }
}
