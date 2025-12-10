
module vanalis::project {
    use sui::event;
    use sui::coin::{Coin, Self};
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use std::string;
    use std::string::String;
    use sui::clock::Clock;

    const E_INVALID_STATUS: u64 = 1002;
    const E_PROJECT_NOT_OPEN: u64 = 1003;
    const E_INSUFFICIENT_REWARD_POOL: u64 = 1004;
    const E_NOT_CURATOR: u64 = 1005;
    const E_DEADLINE_PASSED: u64 = 1006;
    const E_INVALID_AMOUNT: u64 = 1007;
    const E_DEADLINE_ALREADY_PASSED: u64 = 1008;
    
    const STATUS_COMING_SOON: u8 = 0;
    const STATUS_OPEN: u8 = 1;
    const STATUS_COMPLETED: u8 = 2;
    const STATUS_CLOSED: u8 = 3;

    const SUBMISSION_PENDING: u8 = 0;
    const SUBMISSION_APPROVED: u8 = 1;
    const SUBMISSION_REJECTED: u8 = 2;

    public struct ProjectRegistry has key {
        id: UID,
        total_projects: u64,
        projects: Table<ID, address>, // project_id -> creator address
    }

    public struct Project has key {
        id: UID,
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
        contributors: vector<address>,
        isListed: bool,
        hasDataset: bool,
        
        created_at: u64,
        deadline: u64,
    }

    public struct Submission has key {
        id: UID,
        project_id: ID,
        contributor: address,
        
        // Walrus blob references
        preview_blob_id: String,

        full_dataset_path: String,
        full_dataset_public_key: String,
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

    // EVENTS
    public struct ProjectCreatedEvent has copy, drop {
        project_id: ID,
        curator: address,
        title: String,
        description: String,
        submission_requirements: vector<String>,
        data_type: String,
        category: String,
        image_url: String,

        total_reward_pool: u64,
        reward_per_submission: u64,
        
        target_submissions: u64,
        status: u8,
        submissions_count: u64,
        approved_count: u64,
        rejected_count: u64,
        isListed: bool,
        hasDataset: bool,
        
        created_at: u64,
        deadline: u64,
    }

    public struct SubmissionReceivedEvent has copy, drop {
        project_id: ID,
        submission_id: ID,
        full_dataset_public_key: String,
        contributor: address,
        submitted_at: u64,
    }

    public struct SubmissionReviewedEvent has copy, drop {
        project_id: ID,
        submission_id: ID,
        approved: bool,
        reward_paid: u64,
        reviewed_at: u64,
    }

    public struct ProjectClosedEvent has copy, drop {
        project_id: ID,
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

        let total_projects = registry.total_projects + 1;
        let creator = tx_context::sender(ctx);
        let current_timestamp = clock.timestamp_ms();

        let project = Project {
            id: object::new(ctx),
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
            contributors: vector::empty<address>(),
            isListed: false,
            hasDataset: false,
            
            created_at: current_timestamp,            
            deadline,
        };

        registry.total_projects = total_projects;
        table::add(&mut registry.projects, object::id(&project), creator);

        event::emit(ProjectCreatedEvent {
            project_id: object::id(&project),
            curator: creator,
            title: project.title,
            description: project.description,
            submission_requirements: project.submission_requirements,
            data_type: project.data_type,
            category: project.category,
            image_url: project.image_url,
            total_reward_pool: reward_amount,
            reward_per_submission: project.reward_per_submission,
            target_submissions,
            status: project.status,
            submissions_count: project.submissions_count,
            approved_count: project.approved_count,
            rejected_count: project.rejected_count,
            isListed: project.isListed,
            hasDataset: project.hasDataset,
            created_at: current_timestamp,
            deadline,
        });

        transfer::share_object(project);
    }

    public fun submit_data(
        project: &mut Project,
        preview_blob_id: String,
        full_dataset_path: String,
        full_dataset_public_key: String,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let current_timestamp = clock.timestamp_ms();

        assert!(project.status == STATUS_OPEN, E_PROJECT_NOT_OPEN);
        assert!(current_timestamp <= project.deadline, E_DEADLINE_ALREADY_PASSED);

        let submission_count = project.submissions_count + 1;
        let contributor = tx_context::sender(ctx);

        let submission = Submission {
            id: object::new(ctx),
            project_id: object::id(project),
            contributor,
            
            preview_blob_id,
            full_dataset_path,
            full_dataset_public_key,
            status: SUBMISSION_PENDING,
            reward_paid: 0,
            
            submitted_at: current_timestamp,
            reviewed_at: 0,
        };

        project.submissions_count = submission_count;

        event::emit(SubmissionReceivedEvent {
            project_id: object::id(project),
            submission_id: object::id(&submission),
            full_dataset_public_key: submission.full_dataset_public_key,
            contributor,
            submitted_at: current_timestamp,
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

        // Add contributor to vector if not already present
        let mut found = false;
        let len = vector::length(&project.contributors);
        let mut i = 0;
        while (i < len) {
            if (*vector::borrow(&project.contributors, i) == contributor) {
                found = true;
                break
            };
            i = i + 1;
        };
        if (!found) {
            vector::push_back(&mut project.contributors, contributor);
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
        let current_timestamp = clock.timestamp_ms();

        assert!(project.status == STATUS_OPEN, E_PROJECT_NOT_OPEN);
        assert!(project.curator == tx_context::sender(ctx), E_NOT_CURATOR);
        assert!(submission.status == SUBMISSION_PENDING, E_INVALID_STATUS);

        submission.reviewed_at = current_timestamp;

        let contributor = submission.contributor;
        
        // Extract IDs before mutable borrows
        let project_id = object::id(project);
        let submission_id = object::id(submission);

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
            project.hasDataset = true;

            let reward_coin = withdraw(&mut project.reward_pool, project.reward_per_submission);
            let collected_coin = coin::from_balance(reward_coin, ctx);
            
            transfer::public_transfer(collected_coin, contributor);
            
            submission.reward_paid = project.reward_per_submission;
            project.rewards_paid_out = project.rewards_paid_out + project.reward_per_submission;
            project.approved_count = project.approved_count + 1;
            
            stats_ref.approved_count = stats_ref.approved_count + 1;
            stats_ref.total_earned = stats_ref.total_earned + project.reward_per_submission;

            event::emit(SubmissionReviewedEvent {
                project_id,
                submission_id,
                approved: true,
                reward_paid: project.reward_per_submission,
                reviewed_at: current_timestamp,
            });

            if(project.target_submissions <= stats_ref.approved_count){
               project.status = STATUS_COMPLETED; 
            }
        } else {
            submission.status = SUBMISSION_REJECTED;
            project.rejected_count = project.rejected_count + 1;

            event::emit(SubmissionReviewedEvent {
                project_id,
                submission_id,
                approved: false,
                reward_paid: 0,
                reviewed_at: current_timestamp,
            });
        }
    }

    /// Withdraw remaining reward for Curator
    public fun withdraw_remaining_rewards(
        project: &mut Project,
        ctx: &mut TxContext
    ) {
        assert!(project.curator == tx_context::sender(ctx), E_NOT_CURATOR);
        assert!(project.status == STATUS_OPEN, E_PROJECT_NOT_OPEN);
        
        let remaining = balance::value(&project.reward_pool);
        assert!(remaining > 0, E_INVALID_AMOUNT);
        
        let remaining_coin = withdraw(&mut project.reward_pool, remaining);
        let withdraw_coin = coin::from_balance(remaining_coin, ctx);
        transfer::public_transfer(withdraw_coin, project.curator);
        project.status = STATUS_CLOSED;
        
        event::emit(ProjectClosedEvent {
            project_id: object::id(project),
        }) 
    }

    public fun withdraw<T>(self: &mut Balance<T>, value: u64): Balance<T> {
        balance::split(self, value)
    }

    // Public getter functions for marketplace access
    public fun get_status(project: &Project): u8 {
        project.status
    }

    public fun get_curator(project: &Project): address {
        project.curator
    }

    public fun get_deadline(project: &Project): u64 {
        project.deadline
    }

    public fun status_coming_soon(): u8 {
        STATUS_COMING_SOON
    }

    public fun status_open(): u8 {
        STATUS_OPEN
    }

    public fun status_completed(): u8 {
        STATUS_COMPLETED
    }
    
    public fun status_closed(): u8 {
        STATUS_CLOSED
    }

    // Getter functions for treasury/marketplace access
    public fun get_approved_count(project: &Project): u64 {
        project.approved_count
    }

    public fun get_contributor_approved_count(project: &Project, contributor: address): u64 {
        if (table::contains(&project.contributor_stats, contributor)) {
            let stats = table::borrow(&project.contributor_stats, contributor);
            stats.approved_count
        } else {
            0
        }
    }

    public fun get_contributors(project: &Project): vector<address> {
        project.contributors
    }

    public fun set_is_listed(project: &mut Project, isListed: bool) {
        project.isListed = isListed
    }

    public fun get_has_dataset(project: &Project): bool {
        project.hasDataset
    }
}
