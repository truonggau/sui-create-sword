module custom_transfer::my_module {
    // Part 1: imports
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;


    const MIN_FEE: u64 = 1000;
    // Part 2: struct definitions
    struct Sword has key, store {
        id: UID,
        magic: u64,
        strength: u64,
    }

    struct Forge has key, store {
        id: UID,
        swords_created: u64,
    }

    struct SwordWrapper has key {
        id: UID,
        original_owner: address,
        to_swap: Sword,
        fee: Balance<SUI>,
    }

    // Part 3: module initializer to be executed when this module is published
    fun init(ctx: &mut TxContext) {
        let admin = Forge {
            id: object::new(ctx),
            swords_created: 0,
        };
        // transfer the forge object to the module/package publisher
        transfer::transfer(admin, tx_context::sender(ctx))
    }

    // Part 4: accessors required to read the struct attributes
    public fun magic(self: &Sword): u64 {
        self.magic
    }

    public fun strength(self: &Sword): u64 {
        self.strength
    }

    public fun swords_created(self: &Forge): u64 {
        self.swords_created
    }

     // Part 5: new Forge
    fun new(ctx: &mut TxContext): Forge {
        Forge {
            id: object::new(ctx),
            swords_created: 0,
        }
    }

    public entry fun sword_create(magic: u64, strength: u64, recipient: address, forge: &mut Forge, ctx: &mut TxContext) {
        use sui::transfer;

        // add sword created
        forge.swords_created = forge.swords_created + 1;

        // create a sword
        let sword = Sword {
            id: object::new(ctx),
            magic: magic,
            strength: strength,
        };
        // transfer the sword
        transfer::transfer(sword, recipient);
    }

    public entry fun sword_transfer(sword: Sword, recipient: address, _ctx: &mut TxContext) {
        use sui::transfer;
        // transfer the sword
        transfer::transfer(sword, recipient);
    }

    public entry fun request_swap(sword: Sword, fee: Coin<SUI>, service_address: address, ctx: &mut TxContext) {
        assert!(coin::value(&fee) >= MIN_FEE, 0);
        let wrapper = SwordWrapper {
            id: object::new(ctx),
            original_owner: tx_context::sender(ctx),
            to_swap: sword,
            fee: coin::into_balance(fee),
        };
        transfer::transfer(wrapper, service_address);
    }

    public entry fun execute_swap(wrapper1: SwordWrapper, wrapper2: SwordWrapper, ctx: &mut TxContext) {

        // Unpack both wrappers, cross send them to the other owner.
        let SwordWrapper {
            id: id1,
            original_owner: original_owner1,
            to_swap: object1,
            fee: fee1,
        } = wrapper1;

        let SwordWrapper {
            id: id2,
            original_owner: original_owner2,
            to_swap: object2,
            fee: fee2,
        } = wrapper2;

        // Perform the swap.
        transfer::transfer(object1, original_owner2);
        transfer::transfer(object2, original_owner1);

        // Service provider takes the fee.
        let service_address = tx_context::sender(ctx);
        balance::join(&mut fee1, fee2);
        transfer::transfer(coin::from_balance(fee1, ctx), service_address);

        // Effectively delete the wrapper objects.
        object::delete(id1);
        object::delete(id2);
    }

    // part 5: public/ entry functions (introduced later in the tutorial)
    // part 6: private functions (if any)
    #[test]
    public fun test_sword_create() {
        use sui::tx_context;
        use sui::transfer;

        // create a dummy TxContext for testing
        let ctx = tx_context::dummy();

        // create a sword
        let sword = Sword {
            id: object::new(&mut ctx),
            magic: 42,
            strength: 7,
        };

        // check if accessor functions return correct values
        assert!(magic(&sword) == 42 && strength(&sword) == 7, 1);
        let dummy_address = @0xCAFE;
        transfer::transfer(sword, dummy_address);
    }

    #[test]
    fun test_sword_transactions() {
        use sui::test_scenario;
        use std::debug;
        // create test addresses representing users
        let admin = @0xBABE;
        let initial_owner = @0xCAFE;
        let final_owner = @0xFACE;
        // first transaction to emulate module initialization
        let scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;
        {
            init(test_scenario::ctx(scenario));
        };
        // second transaction executed by admin to create the sword
        test_scenario::next_tx(scenario, admin);
        {
            let forge = test_scenario::take_from_sender<Forge>(scenario);
            debug::print(&forge);
            let mut_forge = &mut forge;
            // create the sword and transfer it to the initial owner
            sword_create(42, 7, initial_owner, mut_forge, test_scenario::ctx(scenario));
            debug::print(mut_forge);
            assert!(swords_created(mut_forge) == 1, 1);
            test_scenario::return_to_sender(scenario, forge)
        };
        // second transaction 2 executed by admin to create the 2nd sword
        test_scenario::next_tx(scenario, admin);
        {
            let forge = test_scenario::take_from_sender<Forge>(scenario);
            let mut_forge = &mut forge;
            // create the sword and transfer it to the initial owner
            sword_create(34, 4, initial_owner, mut_forge, test_scenario::ctx(scenario));
            debug::print(mut_forge); 
            assert!(swords_created(mut_forge) == 2, 1);
            test_scenario::return_to_sender(scenario, forge)
        };
        // third transaction executed by the initial sword owner
        test_scenario::next_tx(scenario, initial_owner);
        {
            // extract the sword owned by the initial owner
            let sword = test_scenario::take_from_sender<Sword>(scenario);
            // transfer the sword to the final owner
            transfer::transfer(sword, final_owner);
        };
        // fourth transaction executed by the final sword owner
        test_scenario::next_tx(scenario, final_owner);
        {
            // extract the sword owned by the final owner
            let sword = test_scenario::take_from_sender<Sword>(scenario);
            debug::print(&sword);
            // verify that the sword has expected properties
            assert!(magic(&sword) == 34 && strength(&sword) == 4, 1);
            // return the sword to the object pool (it cannot be simply "dropped")
            test_scenario::return_to_sender(scenario, sword)
        };
        test_scenario::end(scenario_val);
    }
}