module vanalis::treasury {
  use sui::coin::{Self, Coin};
  use sui::balance::{Self, Balance};
  use sui::table::{Self, Table};
  use sui::event;
  use vanalis::project;

  const E_NOT_PLATFORM_OWNER: u64 = 3001;

  public struct PlatformTreasury has key {
    id: UID,
    platform_owner: address,
    platform_balance: Balance<sui::sui::SUI>,
    treasury: Table<address, Treasury>,
    curator_fee_percent: u64,
    platform_fee_percent: u64,
    percentage_denominator: u64,
    total_contributor_collected: u64,
    total_curator_collected: u64,
    total_platform_collected: u64,
  }

  public struct Treasury has key, store {
    id: UID,
    owner: address,
    contributor_balance: Balance<sui::sui::SUI>,
    curator_balance: Balance<sui::sui::SUI>,
    total_contributor_collected: u64,
    total_curator_collected: u64,
  }

  public struct TreasuryCreatedEvent has copy, drop {
    id: ID,
    owner: address,
  }

  fun init(ctx: &mut TxContext) {
    let registry = PlatformTreasury {
      id: object::new(ctx),
      platform_owner: tx_context::sender(ctx),
      platform_balance: balance::zero(),
      treasury: table::new(ctx),
      curator_fee_percent: 5000,
      platform_fee_percent: 2000,
      percentage_denominator: 10000,
      total_contributor_collected: 0,
      total_curator_collected: 0,
      total_platform_collected: 0,
    };
    transfer::share_object(registry);
  }

  #[test_only]
  public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
  }

  public fun get_treasury(platform: &mut PlatformTreasury, owner: address, ctx: &mut TxContext): &mut Treasury {
    if (!table::contains(&platform.treasury, owner)) {
      create_treasury(platform, owner, ctx);
    };
    table::borrow_mut(&mut platform.treasury, owner)
  }

  public fun transfer_platform_ownership(platform: &mut PlatformTreasury, new_owner: address, ctx: &mut TxContext) {
    assert!(tx_context::sender(ctx) == platform.platform_owner, E_NOT_PLATFORM_OWNER);
    platform.platform_owner = new_owner;
  }

  fun create_treasury(platform: &mut PlatformTreasury, owner: address, ctx: &mut TxContext) {
    let treasury = Treasury {
      id: object::new(ctx),
      owner,
      contributor_balance: balance::zero(),
      curator_balance: balance::zero(),
      total_contributor_collected: 0,
      total_curator_collected: 0,
    };

    event::emit(TreasuryCreatedEvent {
      id: object::id(&treasury),
      owner,
    });

    table::add(&mut platform.treasury, owner, treasury);
  }

  public(package) fun give_submission_reward(platform: &mut PlatformTreasury, owner: address, coin: Coin<sui::sui::SUI>, ctx: &mut TxContext) {
    let treasury = get_treasury(platform, owner, ctx);
    let coin_balance = coin::into_balance(coin);
    let coin_value = balance::value(&coin_balance);

    balance::join(&mut treasury.contributor_balance, coin_balance);

    treasury.total_contributor_collected = treasury.total_contributor_collected + coin_value;
    platform.total_contributor_collected = platform.total_contributor_collected + coin_value;
  }

  public(package) fun distribute_earnings_from_sale(
    platform: &mut PlatformTreasury,
    project: &project::Project,
    curator_address: address,
    mut payment_coin: Coin<sui::sui::SUI>,
    ctx: &mut TxContext
  ) {

    let payment_value = coin::value(&payment_coin);
    let platform_fee = payment_value * platform.platform_fee_percent / platform.percentage_denominator;
    let curator_fee = payment_value * platform.curator_fee_percent / platform.percentage_denominator;

    // Get coins for platform & curator
    let platform_fee_coin = coin::split(&mut payment_coin, platform_fee, ctx);
    let curator_fee_coin = coin::split(&mut payment_coin, curator_fee, ctx);

    // Update platform balance & total platform collected
    let platform_balance = coin::into_balance(platform_fee_coin);
    balance::join(&mut platform.platform_balance, platform_balance);
    platform.total_platform_collected = platform.total_platform_collected + platform_fee;

    // Update curator balance & total curator collected
    let treasury = get_treasury(platform, curator_address, ctx);
    let curator_balance = coin::into_balance(curator_fee_coin);
    balance::join(&mut treasury.curator_balance, curator_balance);
    treasury.total_curator_collected = treasury.total_curator_collected + curator_fee;

    // Distribute contributor fee to contributors based on approved submissions
    let total_approved_count = project::get_approved_count(project);
    let remaining_contributor_coin_value = coin::value(&payment_coin);
    
    if (total_approved_count > 0 && remaining_contributor_coin_value > 0) {
      let contributors = project::get_contributors(project);
      let len = vector::length(&contributors);
      let mut i = 0;
      
      while (i < len) {
        let contributor_address = *vector::borrow(&contributors, i);
        let contributor_approved_count = project::get_contributor_approved_count(project, contributor_address);
        
        if (contributor_approved_count > 0) {
          // Calculate share: (contributor_approved_count * remaining_contributor_coin_value) / total_approved_count
          let contributor_share = (contributor_approved_count * remaining_contributor_coin_value) / total_approved_count;
          
          if (contributor_share > 0) {
            let current_coin_value = coin::value(&payment_coin);
            if (current_coin_value >= contributor_share) {
              let contributor_coin = coin::split(&mut payment_coin, contributor_share, ctx);
              give_submission_reward(platform, contributor_address, contributor_coin, ctx);
            };
          };
        };
        i = i + 1;
      };
      
      // If there's any remaining coin due to rounding, send to platform
      let remaining_value = coin::value(&payment_coin);
      let remaining_balance = coin::into_balance(payment_coin);
      if (remaining_value > 0) {
        balance::join(&mut platform.platform_balance, remaining_balance);
        platform.total_platform_collected = platform.total_platform_collected + remaining_value;
      } else {
        // Join empty balance to platform (consumes the balance)
        balance::join(&mut platform.platform_balance, remaining_balance);
      };
    } else {
      // If no approved submissions, send contributor fee to platform
      let contributor_balance = coin::into_balance(payment_coin);
      balance::join(&mut platform.platform_balance, contributor_balance);
      platform.total_platform_collected = platform.total_platform_collected + remaining_contributor_coin_value;
    };
  }
}