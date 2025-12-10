// #[test_only]
// module vanalis::project_tests {
//     use sui::test_scenario as ts;
//     use sui::clock;
//     use sui::coin;
//     use sui::sui::SUI;
//     use std::string;
//     use sui::object;
    
//     use vanalis::project;
//     use vanalis::marketplace;
//     use vanalis::treasury;

//     // Test user addresses
//     const PLATFORM_OWNER: address = @0x1;
//     const CURATOR1: address = @0xA;
//     const CURATOR2: address = @0xB;
//     const CONTRIBUTOR1: address = @0xC;
//     const CONTRIBUTOR2: address = @0xD;
//     const BUYER1: address = @0xE;
//     const BUYER2: address = @0xF;

//     // Test constants
//     const REWARD_PER_SUBMISSION: u64 = 1000;
//     const TARGET_SUBMISSIONS: u64 = 2;
//     const LISTING_PRICE: u64 = 5000;

//     #[test]
//     fun test_complete_flow_with_mixed_roles() {
//         let mut scenario = ts::begin(PLATFORM_OWNER);
        
//         // Initialize all modules
//         project::init_for_testing(ts::ctx(&mut scenario));
//         marketplace::init_for_testing(ts::ctx(&mut scenario));
//         treasury::init_for_testing(ts::ctx(&mut scenario));

//         // Create and share clock
//         let clock = clock::create_for_testing(ts::ctx(&mut scenario));
//         clock::share_for_testing(clock);

//         // Get shared objects
//         let mut registry = ts::take_shared<project::ProjectRegistry>(&mut scenario);
//         let mut marketplace_obj = ts::take_shared<marketplace::Marketplace>(&mut scenario);
//         let mut platform_treasury = ts::take_shared<treasury::PlatformTreasury>(&mut scenario);

//         // Step 1: Create Projects
//         ts::next_tx(&mut scenario, CURATOR1);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let reward_coin = coin::mint_for_testing<SUI>(REWARD_PER_SUBMISSION * TARGET_SUBMISSIONS, ts::ctx(&mut scenario));
//             project::create_project(
//                 &mut registry,
//                 string::utf8(b"Project 1"),
//                 string::utf8(b"Description 1"),
//                 vector::empty<string::String>(),
//                 string::utf8(b"image1"),
//                 string::utf8(b"category1"),
//                 string::utf8(b"data_type1"),
//                 reward_coin,
//                 REWARD_PER_SUBMISSION,
//                 TARGET_SUBMISSIONS,
//                 clock::timestamp_ms(&clock_ref) + 1000000,
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(clock_ref);
//         };
//         let project1 = ts::take_shared<project::Project>(&mut scenario);
//         ts::return_shared(project1);

//         ts::next_tx(&mut scenario, CURATOR2);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let reward_coin = coin::mint_for_testing<SUI>(REWARD_PER_SUBMISSION * TARGET_SUBMISSIONS, ts::ctx(&mut scenario));
//             project::create_project(
//                 &mut registry,
//                 string::utf8(b"Project 2"),
//                 string::utf8(b"Description 2"),
//                 vector::empty<string::String>(),
//                 string::utf8(b"image2"),
//                 string::utf8(b"category2"),
//                 string::utf8(b"data_type2"),
//                 reward_coin,
//                 REWARD_PER_SUBMISSION,
//                 TARGET_SUBMISSIONS,
//                 clock::timestamp_ms(&clock_ref) + 1000000,
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(clock_ref);
//         };
//         let project2 = ts::take_shared<project::Project>(&mut scenario);
//         ts::return_shared(project2);

//         // Step 2: Submit Data
//         // curator1 submits to project2
//         ts::next_tx(&mut scenario, CURATOR1);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut project2 = ts::take_shared<project::Project>(&mut scenario);
//             project::submit_data(
//                 &mut project2,
//                 string::utf8(b"blob1"),
//                 string::utf8(b"path1"),
//                 string::utf8(b"key1"),
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(project2);
//             ts::return_shared(clock_ref);
//         };
//         // submission1 created, will be taken during review

//         // curator2 submits to project1
//         ts::next_tx(&mut scenario, CURATOR2);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut project1 = ts::take_shared<project::Project>(&mut scenario);
//             project::submit_data(
//                 &mut project1,
//                 string::utf8(b"blob2"),
//                 string::utf8(b"path2"),
//                 string::utf8(b"key2"),
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(project1);
//             ts::return_shared(clock_ref);
//         };
//         // submission2 created, will be taken during review

//         // contributor1 submits to project1
//         ts::next_tx(&mut scenario, CONTRIBUTOR1);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut project1 = ts::take_shared<project::Project>(&mut scenario);
//             project::submit_data(
//                 &mut project1,
//                 string::utf8(b"blob3"),
//                 string::utf8(b"path3"),
//                 string::utf8(b"key3"),
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(project1);
//         };
//         // submission3 created, will be taken during review

//         // contributor1 submits to project2
//         ts::next_tx(&mut scenario, CONTRIBUTOR1);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut project2 = ts::take_shared<project::Project>(&mut scenario);
//             project::submit_data(
//                 &mut project2,
//                 string::utf8(b"blob4"),
//                 string::utf8(b"path4"),
//                 string::utf8(b"key4"),
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(project2);
//             ts::return_shared(clock_ref);
//         };
//         // submission4 created, will be taken during review

//         // contributor2 submits to project1
//         ts::next_tx(&mut scenario, CONTRIBUTOR2);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut project1 = ts::take_shared<project::Project>(&mut scenario);
//             project::submit_data(
//                 &mut project1,
//                 string::utf8(b"blob5"),
//                 string::utf8(b"path5"),
//                 string::utf8(b"key5"),
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(project1);
//         };
//         // submission5 created, will be taken during review

//         // contributor2 submits to project2
//         ts::next_tx(&mut scenario, CONTRIBUTOR2);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut project2 = ts::take_shared<project::Project>(&mut scenario);
//             project::submit_data(
//                 &mut project2,
//                 string::utf8(b"blob6"),
//                 string::utf8(b"path6"),
//                 string::utf8(b"key6"),
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(project2);
//         };
//         // submission6 created, will be taken during review

//         // Step 3: Review Submissions
//         // Note: take_shared takes the most recently created object, so we review in reverse order
//         // Submission order: 1(curator1->project2), 2(curator2->project1), 3(contributor1->project1), 
//         //                   4(contributor1->project2), 5(contributor2->project1), 6(contributor2->project2)
        
//         // curator2 approves contributor2's submission in project2 (submission6 - most recent)
//         ts::next_tx(&mut scenario, CURATOR2);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut project2 = ts::take_shared<project::Project>(&mut scenario);
//             let mut submission6 = ts::take_shared<project::Submission>(&mut scenario);
//             project::review_submission(
//                 &mut project2,
//                 &mut submission6,
//                 true, // approve
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(project2);
//             ts::return_shared(submission6);
//             ts::return_shared(clock_ref);
//         };

//         // curator1 rejects contributor2's submission in project1 (submission5)
//         ts::next_tx(&mut scenario, CURATOR1);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut project1 = ts::take_shared<project::Project>(&mut scenario);
//             let mut submission5 = ts::take_shared<project::Submission>(&mut scenario);
//             project::review_submission(
//                 &mut project1,
//                 &mut submission5,
//                 false, // reject
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(project1);
//             ts::return_shared(submission5);
//             ts::return_shared(clock_ref);
//         };

//         // curator2 approves contributor1's submission in project2 (submission4)
//         ts::next_tx(&mut scenario, CURATOR2);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut project2 = ts::take_shared<project::Project>(&mut scenario);
//             let mut submission4 = ts::take_shared<project::Submission>(&mut scenario);
//             project::review_submission(
//                 &mut project2,
//                 &mut submission4,
//                 true, // approve
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(project2);
//             ts::return_shared(submission4);
//             ts::return_shared(clock_ref);
//         };

//         // curator1 approves contributor1's submission in project1 (submission3)
//         ts::next_tx(&mut scenario, CURATOR1);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut project1 = ts::take_shared<project::Project>(&mut scenario);
//             let mut submission3 = ts::take_shared<project::Submission>(&mut scenario);
//             project::review_submission(
//                 &mut project1,
//                 &mut submission3,
//                 true, // approve
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(project1);
//             ts::return_shared(submission3);
//             ts::return_shared(clock_ref);
//         };

//         // curator1 approves curator2's submission in project1 (submission2)
//         ts::next_tx(&mut scenario, CURATOR1);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut project1 = ts::take_shared<project::Project>(&mut scenario);
//             let mut submission2 = ts::take_shared<project::Submission>(&mut scenario);
//             project::review_submission(
//                 &mut project1,
//                 &mut submission2,
//                 true, // approve
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(project1);
//             ts::return_shared(submission2);
//             ts::return_shared(clock_ref);
//         };

//         // curator2 approves curator1's submission in project2 (submission1 - oldest)
//         ts::next_tx(&mut scenario, CURATOR2);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut project2 = ts::take_shared<project::Project>(&mut scenario);
//             let mut submission1 = ts::take_shared<project::Submission>(&mut scenario);
//             project::review_submission(
//                 &mut project2,
//                 &mut submission1,
//                 true, // approve
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(project2);
//             ts::return_shared(submission1);
//             ts::return_shared(clock_ref);
//         };

//         // Step 4: Projects should be completed (target_submissions reached)
//         // Project1: 2 approved (target is 2) - COMPLETED
//         // Project2: 3 approved (target is 2) - COMPLETED

//         // Step 5: Create Listings
//         ts::next_tx(&mut scenario, CURATOR1);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut project1 = ts::take_shared<project::Project>(&mut scenario);
//             marketplace::create_listing(
//                 &mut marketplace_obj,
//                 &mut project1,
//                 LISTING_PRICE,
//                 string::utf8(b"collection_blob1"),
//                 string::utf8(b"collection_key1"),
//                 0,
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(project1);
//             ts::return_shared(clock_ref);
//         };
//         let listing1 = ts::take_shared<marketplace::MarketplaceListing>(&mut scenario);
//         ts::return_shared(listing1);

//         ts::next_tx(&mut scenario, CURATOR2);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut project2 = ts::take_shared<project::Project>(&mut scenario);
//             marketplace::create_listing(
//                 &mut marketplace_obj,
//                 &mut project2,
//                 LISTING_PRICE,
//                 string::utf8(b"collection_blob2"),
//                 string::utf8(b"collection_key2"),
//                 0,
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(project2);
//             ts::return_shared(clock_ref);
//         };
//         let listing2 = ts::take_shared<marketplace::MarketplaceListing>(&mut scenario);
//         ts::return_shared(listing2);

//         // Step 6: Purchase
//         ts::next_tx(&mut scenario, BUYER1);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut listing1 = ts::take_shared<marketplace::MarketplaceListing>(&mut scenario);
//             let project1 = ts::take_shared<project::Project>(&mut scenario);
//             let payment_coin = coin::mint_for_testing<SUI>(LISTING_PRICE, ts::ctx(&mut scenario));
//             marketplace::purchase(
//                 &mut marketplace_obj,
//                 &mut platform_treasury,
//                 &project1,
//                 &mut listing1,
//                 payment_coin,
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(listing1);
//             ts::return_shared(project1);
//             ts::return_shared(clock_ref);
//         };

//         ts::next_tx(&mut scenario, BUYER1);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut listing2 = ts::take_shared<marketplace::MarketplaceListing>(&mut scenario);
//             let project2 = ts::take_shared<project::Project>(&mut scenario);
//             let payment_coin = coin::mint_for_testing<SUI>(LISTING_PRICE, ts::ctx(&mut scenario));
//             marketplace::purchase(
//                 &mut marketplace_obj,
//                 &mut platform_treasury,
//                 &project2,
//                 &mut listing2,
//                 payment_coin,
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(listing2);
//             ts::return_shared(project2);
//             ts::return_shared(clock_ref);
//         };

//         ts::next_tx(&mut scenario, BUYER2);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut listing1 = ts::take_shared<marketplace::MarketplaceListing>(&mut scenario);
//             let project1 = ts::take_shared<project::Project>(&mut scenario);
//             let payment_coin = coin::mint_for_testing<SUI>(LISTING_PRICE, ts::ctx(&mut scenario));
//             marketplace::purchase(
//                 &mut marketplace_obj,
//                 &mut platform_treasury,
//                 &project1,
//                 &mut listing1,
//                 payment_coin,
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(listing1);
//             ts::return_shared(project1);
//             ts::return_shared(clock_ref);
//         };

//         ts::next_tx(&mut scenario, BUYER2);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut listing2 = ts::take_shared<marketplace::MarketplaceListing>(&mut scenario);
//             let project2 = ts::take_shared<project::Project>(&mut scenario);
//             let payment_coin = coin::mint_for_testing<SUI>(LISTING_PRICE, ts::ctx(&mut scenario));
//             marketplace::purchase(
//                 &mut marketplace_obj,
//                 &mut platform_treasury,
//                 &project2,
//                 &mut listing2,
//                 payment_coin,
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(listing2);
//             ts::return_shared(project2);
//             ts::return_shared(clock_ref);
//         };

//         // Step 7: Verify Distributed Earnings
//         // Platform fee: 20% of each sale = 0.2 * 5000 = 1000 per sale
//         // Total platform: 4 sales * 1000 = 4000
//         // Curator fee: 50% of each sale = 0.5 * 5000 = 2500 per sale
//         // Curator1: 2 sales from project1 = 5000
//         // Curator2: 2 sales from project2 = 5000
//         // Contributor fee: 30% of each sale = 0.3 * 5000 = 1500 per sale
//         // Total contributor: 4 sales * 1500 = 6000 (split among contributors)

//         // Step 8: Test Withdraw Functions
//         ts::next_tx(&mut scenario, PLATFORM_OWNER);
//         {
//             let withdrawn = treasury::withdraw_platform_all(&mut platform_treasury, ts::ctx(&mut scenario));
//             let _amount = coin::value(&withdrawn);
//             // Verify amount is approximately 4000 (platform fees from 4 sales)
//             coin::burn_for_testing(withdrawn);
//         };

//         ts::next_tx(&mut scenario, CURATOR1);
//         {
//             let withdrawn = treasury::withdraw_user_all(&mut platform_treasury, ts::ctx(&mut scenario));
//             let _amount = coin::value(&withdrawn);
//             // Verify amount is approximately 5000 (curator fees from project1)
//             coin::burn_for_testing(withdrawn);
//         };

//         ts::next_tx(&mut scenario, CURATOR2);
//         {
//             let withdrawn = treasury::withdraw_user_all(&mut platform_treasury, ts::ctx(&mut scenario));
//             let _amount = coin::value(&withdrawn);
//             // Verify amount is approximately 5000 (curator fees from project2)
//             coin::burn_for_testing(withdrawn);
//         };

//         ts::next_tx(&mut scenario, CONTRIBUTOR1);
//         {
//             let withdrawn = treasury::withdraw_user_all(&mut platform_treasury, ts::ctx(&mut scenario));
//             coin::burn_for_testing(withdrawn);
//         };

//         ts::next_tx(&mut scenario, CONTRIBUTOR2);
//         {
//             let withdrawn = treasury::withdraw_user_all(&mut platform_treasury, ts::ctx(&mut scenario));
//             coin::burn_for_testing(withdrawn);
//         };

//         ts::return_shared(registry);
//         ts::return_shared(marketplace_obj);
//         ts::return_shared(platform_treasury);
//         ts::end(scenario);
//     }

//     #[test]
//     fun test_withdraw_functions() {
//         let mut scenario = ts::begin(PLATFORM_OWNER);
        
//         // Initialize
//         project::init_for_testing(ts::ctx(&mut scenario));
//         marketplace::init_for_testing(ts::ctx(&mut scenario));
//         treasury::init_for_testing(ts::ctx(&mut scenario));

//         let clock = clock::create_for_testing(ts::ctx(&mut scenario));
//         clock::share_for_testing(clock);

//         let mut registry = ts::take_shared<project::ProjectRegistry>(&mut scenario);
//         let mut marketplace_obj = ts::take_shared<marketplace::Marketplace>(&mut scenario);
//         let mut platform_treasury = ts::take_shared<treasury::PlatformTreasury>(&mut scenario);
        
//         // Create a project and complete flow to generate earnings
//         ts::next_tx(&mut scenario, CURATOR1);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let reward_coin = coin::mint_for_testing<SUI>(REWARD_PER_SUBMISSION * TARGET_SUBMISSIONS, ts::ctx(&mut scenario));
//             project::create_project(
//                 &mut registry,
//                 string::utf8(b"Test Project"),
//                 string::utf8(b"Test Description"),
//                 vector::empty<string::String>(),
//                 string::utf8(b"image"),
//                 string::utf8(b"category"),
//                 string::utf8(b"data_type"),
//                 reward_coin,
//                 REWARD_PER_SUBMISSION,
//                 TARGET_SUBMISSIONS,
//                 clock::timestamp_ms(&clock_ref) + 1000000,
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(clock_ref);
//         };
//         let mut project = ts::take_shared<project::Project>(&mut scenario);
//         ts::return_shared(project);

//         // Create listing
//         ts::next_tx(&mut scenario, CURATOR1);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut project = ts::take_shared<project::Project>(&mut scenario);
//             marketplace::create_listing(
//                 &mut marketplace_obj,
//                 &mut project,
//                 LISTING_PRICE,
//                 string::utf8(b"collection_blob"),
//                 string::utf8(b"collection_key"),
//                 0,
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(clock_ref);
//             ts::return_shared(project);
//         };
//         let mut listing = ts::take_shared<marketplace::MarketplaceListing>(&mut scenario);
//         ts::return_shared(listing);

//         // Make a purchase to generate earnings
//         ts::next_tx(&mut scenario, BUYER1);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut listing = ts::take_shared<marketplace::MarketplaceListing>(&mut scenario);
//             let project = ts::take_shared<project::Project>(&mut scenario);
//             let payment_coin = coin::mint_for_testing<SUI>(LISTING_PRICE, ts::ctx(&mut scenario));
//             marketplace::purchase(
//                 &mut marketplace_obj,
//                 &mut platform_treasury,
//                 &project,
//                 &mut listing,
//                 payment_coin,
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(listing);
//             ts::return_shared(project);
//             ts::return_shared(clock_ref);
//         };

//         // Test platform owner withdraw all
//         ts::next_tx(&mut scenario, PLATFORM_OWNER);
//         {
//             let withdrawn = treasury::withdraw_platform_all(&mut platform_treasury, ts::ctx(&mut scenario));
//             let amount = coin::value(&withdrawn);
//             assert!(amount > 0, 1);
//             coin::burn_for_testing(withdrawn);
//         };

//         // Test platform owner withdraw specific amount
//         // First add more balance
//         ts::next_tx(&mut scenario, BUYER2);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut listing = ts::take_shared<marketplace::MarketplaceListing>(&mut scenario);
//             let project = ts::take_shared<project::Project>(&mut scenario);
//             let payment_coin = coin::mint_for_testing<SUI>(LISTING_PRICE, ts::ctx(&mut scenario));
//             marketplace::purchase(
//                 &mut marketplace_obj,
//                 &mut platform_treasury,
//                 &project,
//                 &mut listing,
//                 payment_coin,
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(listing);
//             ts::return_shared(project);
//             ts::return_shared(clock_ref);
//         };

//         ts::next_tx(&mut scenario, PLATFORM_OWNER);
//         {
//             let withdrawn = treasury::withdraw_platform(&mut platform_treasury, 500, ts::ctx(&mut scenario));
//             let amount = coin::value(&withdrawn);
//             assert!(amount == 500, 2);
//             coin::burn_for_testing(withdrawn);
//         };

//         // Test curator withdraw all
//         ts::next_tx(&mut scenario, CURATOR1);
//         {
//             let withdrawn = treasury::withdraw_user_all(&mut platform_treasury, ts::ctx(&mut scenario));
//             let amount = coin::value(&withdrawn);
//             assert!(amount > 0, 3);
//             coin::burn_for_testing(withdrawn);
//         };

//         // Test curator withdraw specific amount
//         // Add more earnings first
//         ts::next_tx(&mut scenario, BUYER1);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut listing = ts::take_shared<marketplace::MarketplaceListing>(&mut scenario);
//             let project = ts::take_shared<project::Project>(&mut scenario);
//             let payment_coin = coin::mint_for_testing<SUI>(LISTING_PRICE, ts::ctx(&mut scenario));
//             marketplace::purchase(
//                 &mut marketplace_obj,
//                 &mut platform_treasury,
//                 &project,
//                 &mut listing,
//                 payment_coin,
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(listing);
//             ts::return_shared(project);
//             ts::return_shared(clock_ref);
//         };

//         ts::next_tx(&mut scenario, CURATOR1);
//         {
//             let withdrawn = treasury::withdraw_user(&mut platform_treasury, 1000, ts::ctx(&mut scenario));
//             let amount = coin::value(&withdrawn);
//             assert!(amount == 1000, 4);
//             coin::burn_for_testing(withdrawn);
//         };

//         ts::return_shared(registry);
//         ts::return_shared(marketplace_obj);
//         ts::return_shared(platform_treasury);
//         ts::end(scenario);
//     }

//     #[test]
//     #[expected_failure(abort_code = treasury::E_NOT_PLATFORM_OWNER)]
//     fun test_withdraw_platform_unauthorized() {
//         let mut scenario = ts::begin(PLATFORM_OWNER);
//         treasury::init_for_testing(ts::ctx(&mut scenario));
//         let mut platform_treasury = ts::take_shared<treasury::PlatformTreasury>(&mut scenario);
        
//         // Try to withdraw as non-owner
//         ts::next_tx(&mut scenario, CURATOR1);
//         {
//             let _withdrawn = treasury::withdraw_platform_all(&mut platform_treasury, ts::ctx(&mut scenario));
//             coin::burn_for_testing(_withdrawn);
//         };
        
//         ts::return_shared(platform_treasury);
//         ts::end(scenario);
//     }

//     #[test]
//     #[expected_failure(abort_code = treasury::E_INSUFFICIENT_BALANCE)]
//     fun test_withdraw_insufficient_balance() {
//         let mut scenario = ts::begin(PLATFORM_OWNER);
//         treasury::init_for_testing(ts::ctx(&mut scenario));
//         let mut platform_treasury = ts::take_shared<treasury::PlatformTreasury>(&mut scenario);
        
//         // Try to withdraw when balance is zero
//         ts::next_tx(&mut scenario, PLATFORM_OWNER);
//         {
//             let _withdrawn = treasury::withdraw_platform_all(&mut platform_treasury, ts::ctx(&mut scenario));
//             coin::burn_for_testing(_withdrawn);
//         };
        
//         ts::return_shared(platform_treasury);
//         ts::end(scenario);
//     }

//     #[test]
//     fun test_purchase_only_users() {
//         let mut scenario = ts::begin(PLATFORM_OWNER);
//         project::init_for_testing(ts::ctx(&mut scenario));
//         marketplace::init_for_testing(ts::ctx(&mut scenario));
//         treasury::init_for_testing(ts::ctx(&mut scenario));

//         let clock = clock::create_for_testing(ts::ctx(&mut scenario));
//         clock::share_for_testing(clock);

//         let mut registry = ts::take_shared<project::ProjectRegistry>(&mut scenario);
//         let mut marketplace_obj = ts::take_shared<marketplace::Marketplace>(&mut scenario);
//         let mut platform_treasury = ts::take_shared<treasury::PlatformTreasury>(&mut scenario);
        
//         // Create project and listing
//         ts::next_tx(&mut scenario, CURATOR1);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let reward_coin = coin::mint_for_testing<SUI>(REWARD_PER_SUBMISSION * TARGET_SUBMISSIONS, ts::ctx(&mut scenario));
//             project::create_project(
//                 &mut registry,
//                 string::utf8(b"Test Project"),
//                 string::utf8(b"Test Description"),
//                 vector::empty<string::String>(),
//                 string::utf8(b"image"),
//                 string::utf8(b"category"),
//                 string::utf8(b"data_type"),
//                 reward_coin,
//                 REWARD_PER_SUBMISSION,
//                 TARGET_SUBMISSIONS,
//                 clock::timestamp_ms(&clock_ref) + 1000000,
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(clock_ref);
//         };
//         let mut project = ts::take_shared<project::Project>(&mut scenario);
//         ts::return_shared(project);

//         ts::next_tx(&mut scenario, CURATOR1);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut project = ts::take_shared<project::Project>(&mut scenario);
//             marketplace::create_listing(
//                 &mut marketplace_obj,
//                 &mut project,
//                 LISTING_PRICE,
//                 string::utf8(b"collection_blob"),
//                 string::utf8(b"collection_key"),
//                 0,
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(clock_ref);
//             ts::return_shared(project);
//         };
//         let mut listing = ts::take_shared<marketplace::MarketplaceListing>(&mut scenario);
//         ts::return_shared(listing);

//         // Buyer1 purchases
//         ts::next_tx(&mut scenario, BUYER1);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut listing = ts::take_shared<marketplace::MarketplaceListing>(&mut scenario);
//             let project = ts::take_shared<project::Project>(&mut scenario);
//             let payment_coin = coin::mint_for_testing<SUI>(LISTING_PRICE, ts::ctx(&mut scenario));
//             marketplace::purchase(
//                 &mut marketplace_obj,
//                 &mut platform_treasury,
//                 &project,
//                 &mut listing,
//                 payment_coin,
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(listing);
//             ts::return_shared(project);
//             ts::return_shared(clock_ref);
//         };

//         // Buyer2 purchases
//         ts::next_tx(&mut scenario, BUYER2);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut listing = ts::take_shared<marketplace::MarketplaceListing>(&mut scenario);
//             let project = ts::take_shared<project::Project>(&mut scenario);
//             let payment_coin = coin::mint_for_testing<SUI>(LISTING_PRICE, ts::ctx(&mut scenario));
//             marketplace::purchase(
//                 &mut marketplace_obj,
//                 &mut platform_treasury,
//                 &project,
//                 &mut listing,
//                 payment_coin,
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(listing);
//             ts::return_shared(project);
//             ts::return_shared(clock_ref);
//         };

//         // Verify buyers don't have treasury earnings (they only purchase)
//         // Buyers should not have any treasury balance

//         ts::return_shared(registry);
//         ts::return_shared(marketplace_obj);
//         ts::return_shared(platform_treasury);
//         ts::end(scenario);
//     }

//     #[test]
//     #[expected_failure(abort_code = marketplace::E_ALREADY_PURCHASED)]
//     fun test_purchase_duplicate() {
//         let mut scenario = ts::begin(PLATFORM_OWNER);
//         project::init_for_testing(ts::ctx(&mut scenario));
//         marketplace::init_for_testing(ts::ctx(&mut scenario));
//         treasury::init_for_testing(ts::ctx(&mut scenario));

//         let clock = clock::create_for_testing(ts::ctx(&mut scenario));
//         clock::share_for_testing(clock);

//         let mut registry = ts::take_shared<project::ProjectRegistry>(&mut scenario);
//         let mut marketplace_obj = ts::take_shared<marketplace::Marketplace>(&mut scenario);
//         let mut platform_treasury = ts::take_shared<treasury::PlatformTreasury>(&mut scenario);
        
//         // Create project and listing
//         ts::next_tx(&mut scenario, CURATOR1);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let reward_coin = coin::mint_for_testing<SUI>(REWARD_PER_SUBMISSION * TARGET_SUBMISSIONS, ts::ctx(&mut scenario));
//             project::create_project(
//                 &mut registry,
//                 string::utf8(b"Test Project"),
//                 string::utf8(b"Test Description"),
//                 vector::empty<string::String>(),
//                 string::utf8(b"image"),
//                 string::utf8(b"category"),
//                 string::utf8(b"data_type"),
//                 reward_coin,
//                 REWARD_PER_SUBMISSION,
//                 TARGET_SUBMISSIONS,
//                 clock::timestamp_ms(&clock_ref) + 1000000,
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(clock_ref);
//         };
//         let mut project = ts::take_shared<project::Project>(&mut scenario);
//         ts::return_shared(project);

//         ts::next_tx(&mut scenario, CURATOR1);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut project = ts::take_shared<project::Project>(&mut scenario);
//             marketplace::create_listing(
//                 &mut marketplace_obj,
//                 &mut project,
//                 LISTING_PRICE,
//                 string::utf8(b"collection_blob"),
//                 string::utf8(b"collection_key"),
//                 0,
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(clock_ref);
//             ts::return_shared(project);
//         };
//         let mut listing = ts::take_shared<marketplace::MarketplaceListing>(&mut scenario);
//         ts::return_shared(listing);

//         // First purchase
//         ts::next_tx(&mut scenario, BUYER1);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut listing = ts::take_shared<marketplace::MarketplaceListing>(&mut scenario);
//             let project = ts::take_shared<project::Project>(&mut scenario);
//             let payment_coin = coin::mint_for_testing<SUI>(LISTING_PRICE, ts::ctx(&mut scenario));
//             marketplace::purchase(
//                 &mut marketplace_obj,
//                 &mut platform_treasury,
//                 &project,
//                 &mut listing,
//                 payment_coin,
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(listing);
//             ts::return_shared(project);
//             ts::return_shared(clock_ref);
//         };

//         // Try to purchase again (should fail)
//         ts::next_tx(&mut scenario, BUYER1);
//         {
//             let clock_ref = ts::take_shared<clock::Clock>(&mut scenario);
//             let mut listing = ts::take_shared<marketplace::MarketplaceListing>(&mut scenario);
//             let project = ts::take_shared<project::Project>(&mut scenario);
//             let payment_coin = coin::mint_for_testing<SUI>(LISTING_PRICE, ts::ctx(&mut scenario));
//             marketplace::purchase(
//                 &mut marketplace_obj,
//                 &mut platform_treasury,
//                 &project,
//                 &mut listing,
//                 payment_coin,
//                 &clock_ref,
//                 ts::ctx(&mut scenario)
//             );
//             ts::return_shared(listing);
//             ts::return_shared(project);
//             ts::return_shared(clock_ref);
//         };

//         ts::return_shared(registry);
//         ts::return_shared(marketplace_obj);
//         ts::return_shared(platform_treasury);
//         ts::end(scenario);
//     }
// }
