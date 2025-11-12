module vanalis::project {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use sui::coin::{Coin, Self};
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use std::vector;
    use std::string::{Self, String};

    const E_NOT_CREATOR: u64 = 1;
    const E_INVALID_STATUS: u64 = 2;
    const E_PROJECT_NOT_OPEN: u64 = 3;
    const E_INSUFFICIENT_REWARD_POOL: u64 = 4;
    const E_NOT_CURATOR: u64 = 5;
    const E_DEADLINE_PASSED: u64 = 6;
    const E_INVALID_AMOUNT: u64 = 7;
    const E_INVALID_ADDRESS: u64 = 8;

    // ============= TYPES =============
    
    /// Status codes for projects
    const STATUS_DRAFT: u8 = 0;
    const STATUS_OPEN: u8 = 1;
    const STATUS_COMPLETED: u8 = 2;
    const STATUS_PUBLISHED: u8 = 3;

    /// Status codes for submissions
    const SUBMISSION_PENDING: u8 = 0;
    const SUBMISSION_APPROVED: u8 = 1;
    const SUBMISSION_REJECTED: u8 = 2;

    // ============= STRUCTS =============

    /// Global state tracker
    public struct ProjectRegistry has key {
        id: UID,
        total_projects: u64,
        projects: Table<u64, address>, // project_id -> creator address
    }

    /// Main data collection project
    public struct Project has key {
        id: UID,
        project_id: u64,
        curator: address,
        
        // Project metadata
        title: String,
        description: String,
        data_type: String,
        quality_criteria: String,
        
        // Reward management
        reward_pool: Balance<sui::sui::SUI>,
        total_reward_pool: u64,
        reward_per_submission: u64,
        rewards_paid_out: u64,
        
        // Project targets
        target_submissions: u64,
        min_quality_score: u8,
        
        // Status tracking
        status: u8,
        submissions_count: u64,
        approved_count: u64,
        rejected_count: u64,
        
        // Final dataset
        final_dataset_blob_id: vector<u8>,
        final_dataset_price: u64,
        
        // Timestamps
        created_at: u64,
        deadline: u64,
    }

    /// Individual data submission
    public struct Submission has key {
        id: UID,
        submission_id: u64,
        project_id: u64,
        contributor: address,
        
        // Walrus blob IDs
        full_dataset_blob_id: vector<u8>,
        preview_blob_id: vector<u8>,
        total_items: u64,
        preview_items: u64,
        
        metadata: String,
        
        // Validation
        status: u8,
        quality_score: u8,
        reviewer_notes: String,
        
        // Payment tracking
        reward_paid: u64,
        
        // Timestamps
        submitted_at: u64,
        reviewed_at: u64,
    }

    /// Contributor statistics
    public struct ContributorStats has key {
        id: UID,
        project_id: u64,
        contributor: address,
        submissions_count: u64,
        approved_count: u64,
        total_earned: u64,
    }

    // ============= EVENTS =============

    public struct ProjectCreatedEvent has copy, drop {
        project_id: u64,
        curator: address,
        reward_pool: u64,
        target_submissions: u64,
        timestamp: u64,
    }

    public struct SubmissionReceivedEvent has copy, drop {
        project_id: u64,
        submission_id: u64,
        contributor: address,
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
        final_dataset_blob_id: vector<u8>,
        price: u64,
        total_contributors: u64,
        timestamp: u64,
    }

    // ============= INITIALIZATION =============

    /// Initialize project registry (call once)
    fun init(ctx: &mut TxContext) {
        let registry = ProjectRegistry {
            id: object::new(ctx),
            total_projects: 0,
            projects: table::new(ctx),
        };
        transfer::share_object(registry);
    }

    // ============= PROJECT CREATION =============

    /// Create new data collection project
    public entry fun create_project(
        registry: &mut ProjectRegistry,
        title: String,
        description: String,
        data_type: String,
        quality_criteria: String,
        reward_coin: Coin<sui::sui::SUI>,
        reward_per_submission: u64,
        target_submissions: u64,
        min_quality_score: u8,
        deadline_epochs: u64,
        ctx: &mut TxContext
    ) {
        // Validate inputs
        assert!(reward_per_submission > 0, E_INVALID_AMOUNT);
        assert!(target_submissions > 0, E_INVALID_AMOUNT);
        assert!(min_quality_score > 0, E_INVALID_AMOUNT);

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
            
            title,
            description,
            data_type,
            quality_criteria,
            
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
            
            final_dataset_blob_id: vector::empty(),
            final_dataset_price: 0,
            
            created_at: current_epoch,
            deadline: current_epoch + deadline_epochs,
        };

        // Update registry
        registry.total_projects = project_id;
        table::add(&mut registry.projects, project_id, creator);

        // Emit event
        event::emit(ProjectCreatedEvent {
            project_id,
            curator: creator,
            reward_pool: reward_amount,
            target_submissions,
            timestamp: current_epoch,
        });

        transfer::share_object(project);
    }

    // ============= SUBMISSION MANAGEMENT =============

    /// Submit data to project
    public entry fun submit_data(
        project: &mut Project,
        full_dataset_blob_id: vector<u8>,
        preview_blob_id: vector<u8>,
        total_items: u64,
        preview_items: u64,
        metadata: String,
        ctx: &mut TxContext
    ) {
        // Validate project status
        assert!(project.status == STATUS_OPEN, E_PROJECT_NOT_OPEN);
        assert!(tx_context::epoch(ctx) < project.deadline, E_DEADLINE_PASSED);
        
        // Validate inputs
        assert!(total_items > 0, E_INVALID_AMOUNT);
        assert!(preview_items > 0, E_INVALID_AMOUNT);
        assert!(preview_items <= total_items, E_INVALID_AMOUNT);

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
            
            metadata,
            
            status: SUBMISSION_PENDING,
            quality_score: 0,
            reviewer_notes: string::utf8(b""),
            
            reward_paid: 0,
            
            submitted_at: current_epoch,
            reviewed_at: 0,
        };

        // Update project counters
        project.submissions_count = project.submissions_count + 1;

        // Emit event
        event::emit(SubmissionReceivedEvent {
            project_id: project.project_id,
            submission_id,
            contributor,
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

    /// Review submission (curator only)
    public entry fun review_submission(
        project: &mut Project,
        submission: &mut Submission,
        stats: &mut ContributorStats,
        approve: bool,
        quality_score: u8,
        reviewer_notes: String,
        ctx: &mut TxContext
    ) {
        // Verify curator
        assert!(project.curator == tx_context::sender(ctx), E_NOT_CURATOR);
        
        // Verify submission is pending
        assert!(submission.status == SUBMISSION_PENDING, E_INVALID_STATUS);
        
        // Validate quality score
        assert!(quality_score <= 100, E_INVALID_AMOUNT);

        let current_epoch = tx_context::epoch(ctx);
        submission.reviewed_at = current_epoch;
        submission.quality_score = quality_score;
        submission.reviewer_notes = reviewer_notes;

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
            
            // Update tracking
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

    // ============= PROJECT PUBLISHING =============

    /// Publish project to marketplace
    public entry fun publish_project(
        project: &mut Project,
        final_dataset_blob_id: vector<u8>,
        price_usdc: u64,
        ctx: &mut TxContext
    ) {
        // Verify curator
        assert!(project.curator == tx_context::sender(ctx), E_NOT_CURATOR);
        
        // Verify project is open
        assert!(project.status == STATUS_OPEN, E_INVALID_STATUS);
        
        // Validate inputs
        assert!(vector::length(&final_dataset_blob_id) > 0, E_INVALID_AMOUNT);
        assert!(price_usdc > 0, E_INVALID_AMOUNT);

        project.status = STATUS_PUBLISHED;
        project.final_dataset_blob_id = final_dataset_blob_id;
        project.final_dataset_price = price_usdc;

        let current_epoch = tx_context::epoch(ctx);

        event::emit(ProjectPublishedEvent {
            project_id: project.project_id,
            final_dataset_blob_id,
            price: price_usdc,
            total_contributors: project.approved_count,
            timestamp: current_epoch,
        });
    }

    /// Withdraw remaining rewards (cleanup)
    public entry fun withdraw_remaining_rewards(
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

    // ============= QUERY FUNCTIONS (View-only) =============

    public fun get_project_status(project: &Project): u8 {
        project.status
    }

    public fun get_submission_status(submission: &Submission): u8 {
        submission.status
    }

    public fun get_project_info(project: &Project): (String, String, u64, u64, u64) {
        (
            project.title,
            project.description,
            project.submissions_count,
            project.approved_count,
            project.total_reward_pool,
        )
    }

    public fun get_contributor_stats(stats: &ContributorStats): (u64, u64, u64) {
        (stats.submissions_count, stats.approved_count, stats.total_earned)
    }

    public fun get_submission_info(submission: &Submission): (address, u64, u64, u8) {
        (submission.contributor, submission.total_items, submission.reward_paid, submission.status)
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
}
