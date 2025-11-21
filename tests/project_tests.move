#[test_only]
module vanalis::project_tests {
    use sui::test_scenario as ts;
    use vanalis::project;
    use sui::clock;

    #[test]
    fun test_create_project() {
        let admin = @0x1;
        let scenario = ts::begin(admin);

        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        clock.share_for_testing();
        
        // TODO:
        project::init_for_testing(ts::ctx(&mut scenario));

        
        ts::end(scenario);
    }
}
