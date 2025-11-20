
module vanalis::project {
    use sui::event;
    use sui::coin::{Coin, Self};
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use std::string;
    use std::string::String;
    use sui::clock::Clock;
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
        title: String,
        description: String,
        submission_requirements: vector<String>,
        data_type: String,
        category: String,
        image_url: String,
        
        reward_pool: Balance<sui::sui::SUI>,
        total_reward_pool: u64,
        reward_per_submission: u64,
        rewards_paid_out: u64,
        
        target_submissions: u64,
        status: u8,
        submissions_count: u64,
        approved_count: u64,
        rejected_count: u64,
        contributor_stats: Table<address, ContributorStats>,
        
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
        
        status: u8,
        
        reward_paid: u64,
        
        submitted_at: u64,
        reviewed_at: u64,
    }

    public struct ContributorStats has store {
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
        listed: bool,
        created_at: u64,
        last_sale_epoch: u64,
    }

    // EVENTS

    public struct ProjectCreatedEvent has copy, drop {
        project_id: u64,
        curator: address,
        title: String,
        description: String,
        submission_requirements: vector<String>,
        data_type: String,
        category: String,
        image_url: String,
        reward_pool: u64,
        
        target_submissions: u64,
        
        status: u8,
        submissions_count: u64,
        approved_count: u64,
        rejected_count: u64,
        
        created_at: u64,
        deadline: u64,
    }

    public struct SubmissionReceivedEvent has copy, drop {
        project_id: u64,
        submission_id: u64,
        contributor: address,
        timestamp: u64,
    }

    public struct SubmissionReviewedEvent has copy, drop {
        submission_id: u64,
        approved: bool,
        reward_paid: u64,
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
        title: String,
        description: String,
        submission_requirements: vector<String>,
        data_type: String,
        category: String,
        image_url: String,
        reward_coin: Coin<sui::sui::SUI>,
        reward_per_submission: u64,
        target_submissions: u64,
        deadline: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(!string::is_empty(&title), E_INVALID_AMOUNT);
        assert!(!string::is_empty(&description), E_INVALID_AMOUNT);
        assert!(!string::is_empty(&data_type), E_INVALID_AMOUNT);
        assert!(!string::is_empty(&category), E_INVALID_AMOUNT);
        assert!(reward_per_submission > 0, E_INVALID_AMOUNT);
        assert!(target_submissions > 0, E_INVALID_AMOUNT);
        assert!(deadline > clock.timestamp_ms(), E_INVALID_AMOUNT);

        let reward_amount = coin::value(&reward_coin);
        let expected_total = reward_per_submission * target_submissions;
        
        assert!(reward_amount >= expected_total, E_INSUFFICIENT_REWARD_POOL);

        let project_id = registry.total_projects + 1;
        let creator = tx_context::sender(ctx);
        let current_timestamp = clock.timestamp_ms();

        let project = Project {
            id: object::new(ctx),
            project_id,
            curator: creator,
            title,
            description,
            submission_requirements,
            data_type,
            category,
            image_url,
            
            reward_pool: coin::into_balance(reward_coin),
            total_reward_pool: reward_amount,
            reward_per_submission,
            rewards_paid_out: 0,
            
            target_submissions,
            
            status: STATUS_OPEN,
            submissions_count: 0,
            approved_count: 0,
            rejected_count: 0,
            contributor_stats: table::new<address, ContributorStats>(ctx),
            
            created_at: current_timestamp,            
            deadline,
        };

        registry.total_projects = project_id;
        table::add(&mut registry.projects, project_id, creator);

        event::emit(ProjectCreatedEvent {
            project_id,
            curator: creator,
            title: project.title,
            description: project.description,
            submission_requirements: project.submission_requirements,
            data_type: project.data_type,
            category: project.category,
            image_url: project.image_url,
            reward_pool: reward_amount,
            target_submissions,
            status: project.status,
            submissions_count: project.submissions_count,
            approved_count: project.approved_count,
            rejected_count: project.rejected_count,
            created_at: current_timestamp,
            deadline,
        });

        transfer::share_object(project);
    }

    public fun submit_data(
        project: &mut Project,
        preview_blob_id: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(project.status == STATUS_OPEN, E_PROJECT_NOT_OPEN);
        assert!(tx_context::epoch(ctx) < project.deadline, E_DEADLINE_PASSED);
        
        let submission_id = project.submissions_count + 1;
        let contributor = tx_context::sender(ctx);
        let current_timestamp = clock.timestamp_ms();

        let submission = Submission {
            id: object::new(ctx),
            submission_id,
            project_id: project.project_id,
            contributor,
            
            full_dataset_blob_id: b"",
            preview_blob_id,
                        
            status: SUBMISSION_PENDING,
            
            reward_paid: 0,
            
            submitted_at: current_timestamp,
            reviewed_at: 0,
        };

        project.submissions_count = project.submissions_count + 1;

        event::emit(SubmissionReceivedEvent {
            project_id: project.project_id,
            submission_id,
            contributor,
            timestamp: current_timestamp,
        });

        if(table::contains(&project.contributor_stats, contributor)) {
            let stats_ref = table::borrow_mut(&mut project.contributor_stats, contributor);
            stats_ref.submissions_count = stats_ref.submissions_count + 1;
        } else {
            let stats = ContributorStats {
                submissions_count: 1,
                approved_count: 0,
                total_earned: 0,
            };
            table::add(&mut project.contributor_stats, contributor, stats);
        };

        transfer::share_object(submission);
    }

    public fun review_submission(
        project: &mut Project,
        submission: &mut Submission,
        approve: bool,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(project.status == STATUS_OPEN, E_PROJECT_NOT_OPEN);
        assert!(project.curator == tx_context::sender(ctx), E_NOT_CURATOR);
        assert!(submission.status == SUBMISSION_PENDING, E_INVALID_STATUS);

        let current_timestamp = clock.timestamp_ms();
        submission.reviewed_at = current_timestamp;

        let contributor = submission.contributor;

        if (!table::contains(&project.contributor_stats, contributor)) {
            let stats = ContributorStats {
                submissions_count: 0,
                approved_count: 0,
                total_earned: 0,
            };
            table::add(&mut project.contributor_stats, contributor, stats);
        };
        let stats_ref = table::borrow_mut(&mut project.contributor_stats, contributor);

        if (approve) {
            submission.status = SUBMISSION_APPROVED;

            let reward_coin = withdraw(&mut project.reward_pool, project.reward_per_submission);
            let collected_coin = coin::from_balance(reward_coin, ctx);
            
            transfer::public_transfer(collected_coin, contributor);
            
            submission.reward_paid = project.reward_per_submission;
            project.rewards_paid_out = project.rewards_paid_out + project.reward_per_submission;
            project.approved_count = project.approved_count + 1;
            
            stats_ref.approved_count = stats_ref.approved_count + 1;
            stats_ref.total_earned = stats_ref.total_earned + project.reward_per_submission;

            event::emit(SubmissionReviewedEvent {
                submission_id: submission.submission_id,
                approved: true,
                reward_paid: project.reward_per_submission,
                timestamp: current_timestamp,
            });

            if(project.target_submissions <= stats_ref.approved_count){
               project.status = STATUS_COMPLETED; 
            }
        } else {
            submission.status = SUBMISSION_REJECTED;
            project.rejected_count = project.rejected_count + 1;

            event::emit(SubmissionReviewedEvent {
                submission_id: submission.submission_id,
                approved: false,
                reward_paid: 0,
                timestamp: current_timestamp,
            });
        }
    }

    /// Withdraw remaining reward for Curator
    public fun withdraw_remaining_rewards(
        project: &mut Project,
        ctx: &mut TxContext
    ) {
        assert!(project.curator == tx_context::sender(ctx), E_NOT_CURATOR);
        
        let remaining = balance::value(&project.reward_pool);
        assert!(remaining > 0, E_INVALID_AMOUNT);
        
        let remaining_coin = withdraw(&mut project.reward_pool, remaining);
        let withdraw_coin = coin::from_balance(remaining_coin, ctx);
        transfer::public_transfer(withdraw_coin, project.curator);
        project.status = STATUS_COMPLETED; 
    }

    // GET FUNCTION

    public fun get_project_status(project: &Project): u8 {
        project.status
    }

    public fun get_submission_status(submission: &Submission): u8 {
        submission.status
    }

    public fun get_project_info(project: &Project): (String, u64, u64, u64) {
        (
            // project.data_type_hash,
            project.category,
            project.submissions_count,
            project.approved_count,
            project.total_reward_pool,
        )
    }

    public fun get_contributor_stats(stats: &ContributorStats): (u64, u64, u64) {
        (stats.submissions_count, stats.approved_count, stats.total_earned)
    }

    public fun get_submission_info(submission: &Submission): (address, u64, u8) {
        (submission.contributor, submission.reward_paid, submission.status)
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

    public fun get_category(project: &Project): String {
        project.category
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

    public fun get_dataset_blob_refs(dataset: &Dataset): (vector<u8>, vector<u8>) {
        (copy dataset.full_dataset_blob_id, copy dataset.preview_blob_id)
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

    public fun withdraw<T>(self: &mut Balance<T>, value: u64): Balance<T> {
        balance::split(self, value)
    }

}
