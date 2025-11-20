#[test_only]
module vanalis::protocol_tests {
    use sui::coin;
    use sui::test_scenario::{Self as ts};
    use vanalis::marketplace;
    use vanalis::pricing;
    use vanalis::project;
    use vanalis::royalty;

    const CURATOR: address = @0xCAFE;
    const CONTRIBUTOR: address = @0xF00D;
    const BUYER: address = @0xBEEF;

    const REWARD_PER_SUBMISSION: u64 = 100;
    const TARGET_SUBMISSIONS: u64 = 5;
    const DEFAULT_DEADLINE: u64 = 5;
    const LISTING_PRICE: u64 = 900;
    const DATASET_PRICE_USDC: u64 = 600;
    const CREATOR_WITHDRAW_SAMPLE: u64 = 200;

    #[test]
    fun test_marketplace_purchase_flow() {
        let mut scenario = ts::begin(CURATOR);
        run_full_sale(&mut scenario);
        verify_post_purchase_state(&mut scenario, LISTING_PRICE, DATASET_PRICE_USDC);
        withdraw_creator_share(&mut scenario, CREATOR_WITHDRAW_SAMPLE);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = vanalis::project::E_DEADLINE_PASSED)]
    fun test_submit_after_deadline_fails() {
        let mut scenario = ts::begin(CURATOR);
        project::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, CURATOR);
        create_project_with_deadline(&mut scenario, 0);

        ts::next_tx(&mut scenario, CONTRIBUTOR);
        let mut proj = ts::take_shared<project::Project>(&scenario);
        project::submit_data(
            &mut proj,
            full_blob(),
            preview_blob(),
            10,
            2,
            submission_metadata(),
            ts::ctx(&mut scenario),
        );
        abort 0
    }

    #[test]
    #[expected_failure(abort_code = vanalis::project::E_NOT_DATA_OWNER)]
    fun test_listing_requires_owner_signature() {
        let mut scenario = ts::begin(CURATOR);
        setup_all_modules(&mut scenario);
        create_project_with_deadline(&mut scenario, DEFAULT_DEADLINE);
        contributor_submit_default(&mut scenario);
        curator_review_latest(&mut scenario, true);
        mint_dataset_default(&mut scenario, DATASET_PRICE_USDC);
        set_oracle_price_default(&mut scenario, LISTING_PRICE);

        ts::next_tx(&mut scenario, BUYER);
        let mut marketplace_obj = ts::take_shared<marketplace::Marketplace>(&scenario);
        let oracle = ts::take_shared<pricing::PriceOracle>(&scenario);
        let mut dataset = ts::take_from_address<project::Dataset>(&scenario, CONTRIBUTOR);
        marketplace::create_listing(
            &mut marketplace_obj,
            &oracle,
            &mut dataset,
            ts::ctx(&mut scenario),
        );
        abort 0
    }

    #[test]
    #[expected_failure(abort_code = vanalis::pricing::E_NOT_ADMIN)]
    fun test_price_oracle_admin_guard() {
        let mut scenario = ts::begin(CURATOR);
        pricing::init_for_testing(ts::ctx(&mut scenario));
        ts::next_tx(&mut scenario, BUYER);

        let mut oracle = ts::take_shared<pricing::PriceOracle>(&scenario);
        pricing::set_price(&mut oracle, dataset_hash(), LISTING_PRICE, ts::ctx(&mut scenario));
        abort 0
    }

    #[test]
    #[expected_failure(abort_code = vanalis::royalty::E_INSUFFICIENT_BALANCE)]
    fun test_royalty_withdraw_overdraft_rejected() {
        let mut scenario = ts::begin(CURATOR);
        run_full_sale(&mut scenario);
        ts::next_tx(&mut scenario, CONTRIBUTOR);
        let mut accumulator = ts::take_shared<royalty::RoyaltyAccumulator>(&scenario);
        let excessive = ((LISTING_PRICE * 40) / 100) + 1;
        royalty::withdraw_royalties_with_coin(
            &mut accumulator,
            excessive,
            ts::ctx(&mut scenario),
        );
        abort 0
    }

    // === Primary happy-path helpers ===

    fun run_full_sale(ts: &mut ts::Scenario) {
        setup_all_modules(ts);
        create_project_with_deadline(ts, DEFAULT_DEADLINE);
        contributor_submit_default(ts);
        curator_review_latest(ts, true);
        mint_dataset_default(ts, DATASET_PRICE_USDC);
        set_oracle_price_default(ts, LISTING_PRICE);
        list_dataset(ts);
        buy_dataset(ts, LISTING_PRICE);
    }

    fun setup_all_modules(ts: &mut ts::Scenario) {
        project::init_for_testing(ts::ctx(ts));
        royalty::init_for_testing(ts::ctx(ts));
        marketplace::init_for_testing(ts::ctx(ts));
        pricing::init_for_testing(ts::ctx(ts));
        ts::next_tx(ts, CURATOR);
    }

    fun create_project_with_deadline(ts: &mut ts::Scenario, deadline_epochs: u64) {
        ts::next_tx(ts, CURATOR);
        let mut registry = ts::take_shared<project::ProjectRegistry>(ts);
        let reward_coin = coin::mint_for_testing(
            REWARD_PER_SUBMISSION * TARGET_SUBMISSIONS,
            ts::ctx(ts),
        );
        project::create_project(
            &mut registry,
            data_type_hash(),
            criteria_hash(),
            reward_coin,
            REWARD_PER_SUBMISSION,
            TARGET_SUBMISSIONS,
            deadline_epochs,
            ts::ctx(ts),
        );
        ts::return_shared(registry);
        ts::next_tx(ts, CURATOR);
    }

    fun contributor_submit_default(ts: &mut ts::Scenario) {
        ts::next_tx(ts, CONTRIBUTOR);
        let mut proj = ts::take_shared<project::Project>(ts);
        project::submit_data(
            &mut proj,
            full_blob(),
            preview_blob(),
            10,
            2,
            submission_metadata(),
            ts::ctx(ts),
        );
        ts::return_shared(proj);
        ts::next_tx(ts, CURATOR);
    }

    fun curator_review_latest(ts: &mut ts::Scenario, approve: bool) {
        ts::next_tx(ts, CURATOR);
        let mut proj = ts::take_shared<project::Project>(ts);
        let mut submission = ts::take_shared<project::Submission>(ts);
        let mut stats = ts::take_shared<project::ContributorStats>(ts);
        project::review_submission(
            &mut proj,
            &mut submission,
            &mut stats,
            approve,
            ts::ctx(ts),
        );
        ts::return_shared(proj);
        ts::return_shared(submission);
        ts::return_shared(stats);
        ts::next_tx(ts, CURATOR);
    }

    fun mint_dataset_default(ts: &mut ts::Scenario, price_usdc: u64) {
        ts::next_tx(ts, CURATOR);
        let mut proj = ts::take_shared<project::Project>(ts);
        let mut submission = ts::take_shared<project::Submission>(ts);
        let mut manager = ts::take_shared<royalty::RoyaltyManager>(ts);
        ts::return_shared(proj);
        ts::return_shared(submission);
        ts::return_shared(manager);
        ts::next_tx(ts, CURATOR);
    }

    fun set_oracle_price_default(ts: &mut ts::Scenario, price: u64) {
        ts::next_tx(ts, CURATOR);
        let mut oracle = ts::take_shared<pricing::PriceOracle>(ts);
        pricing::set_price(&mut oracle, dataset_hash(), price, ts::ctx(ts));
        ts::return_shared(oracle);
        ts::next_tx(ts, CURATOR);
    }

    fun list_dataset(ts: &mut ts::Scenario) {
        ts::next_tx(ts, CONTRIBUTOR);
        let mut market = ts::take_shared<marketplace::Marketplace>(ts);
        let oracle = ts::take_shared<pricing::PriceOracle>(ts);
        let mut dataset = ts::take_from_address<project::Dataset>(ts, CONTRIBUTOR);
        marketplace::create_listing(&mut market, &oracle, &mut dataset, ts::ctx(ts));
        ts::return_shared(market);
        ts::return_shared(oracle);
        ts::return_to_address(CONTRIBUTOR, dataset);
        ts::next_tx(ts, CONTRIBUTOR);
    }

    fun buy_dataset(ts: &mut ts::Scenario, price: u64) {
        ts::next_tx(ts, BUYER);
        let mut market = ts::take_shared<marketplace::Marketplace>(ts);
        let mut treasury = ts::take_shared<marketplace::Treasury>(ts);
        let manager = ts::take_shared<royalty::RoyaltyManager>(ts);
        let mut accumulator = ts::take_shared<royalty::RoyaltyAccumulator>(ts);
        let mut dataset = ts::take_from_address<project::Dataset>(ts, CONTRIBUTOR);
        let mut listing = ts::take_shared<marketplace::MarketplaceListing>(ts);
        let payment = coin::mint_for_testing(price, ts::ctx(ts));
        marketplace::purchase_dataset(
            &mut market,
            &mut treasury,
            &manager,
            &mut accumulator,
            &mut dataset,
            &mut listing,
            payment,
            ts::ctx(ts),
        );
        ts::return_shared(market);
        ts::return_shared(treasury);
        ts::return_shared(manager);
        ts::return_shared(accumulator);
        ts::return_shared(listing);
        ts::return_to_address(CONTRIBUTOR, dataset);
        ts::next_tx(ts, CURATOR);
    }

    fun verify_post_purchase_state(ts: &mut ts::Scenario, price: u64, dataset_price_usdc: u64) {
        ts::next_tx(ts, CURATOR);

        let dataset = ts::take_from_address<project::Dataset>(ts, CONTRIBUTOR);
        assert!(!project::is_dataset_listed(&dataset), 0);
        assert!(project::get_dataset_price_usdc(&dataset) == dataset_price_usdc, 0);
        ts::return_to_address(CONTRIBUTOR, dataset);

        let listing = ts::take_shared<marketplace::MarketplaceListing>(ts);
        assert!(!marketplace::is_listing_active(&listing), 0);
        ts::return_shared(listing);

        let token = ts::take_from_address<marketplace::DatasetAccessToken>(ts, BUYER);
        assert!(marketplace::access_token_project_id(&token) == 1, 0);
        assert!(marketplace::access_token_matches_hash(&token, dataset_hash()), 0);
        ts::return_to_address(BUYER, token);

        let treasury = ts::take_shared<marketplace::Treasury>(ts);
        assert!(marketplace::get_treasury_collected(&treasury) == price / 10, 0);
        ts::return_shared(treasury);

        let accumulator = ts::take_shared<royalty::RoyaltyAccumulator>(ts);
        assert!(royalty::creator_balance(&accumulator) == (price * 40) / 100, 0);
        assert!(royalty::curator_balance(&accumulator) == (price * 50) / 100, 0);
        ts::return_shared(accumulator);
    }

    fun withdraw_creator_share(ts: &mut ts::Scenario, amount: u64) {
        ts::next_tx(ts, CONTRIBUTOR);
        let mut accumulator = ts::take_shared<royalty::RoyaltyAccumulator>(ts);
        royalty::withdraw_royalties_with_coin(&mut accumulator, amount, ts::ctx(ts));
        assert!(
            royalty::creator_balance(&accumulator) == ((LISTING_PRICE * 40) / 100) - amount,
            0,
        );
        ts::return_shared(accumulator);
        ts::next_tx(ts, CURATOR);
    }

    // === Reusable data helpers ===

    fun data_type_hash(): vector<u8> {
        b"vision-dataset"
    }

    fun criteria_hash(): vector<u8> {
        b"quality-threshold"
    }

    fun submission_metadata(): vector<u8> {
        b"submission-metadata"
    }

    fun full_blob(): vector<u8> {
        b"full-dataset-blob"
    }

    fun preview_blob(): vector<u8> {
        b"preview-blob"
    }

    fun dataset_hash(): vector<u8> {
        b"final-dataset-hash"
    }
}
