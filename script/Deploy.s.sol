// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {RitualPassport} from "../src/RitualPassport.sol";
import {AIOracleQuest} from "../src/quests/AIOracleQuest.sol";
import {HTTPDataQuest} from "../src/quests/HTTPDataQuest.sol";
import {SchedulerHeartbeatQuest} from "../src/quests/SchedulerHeartbeatQuest.sol";

/// @notice Deploys RitualPassport + the three quest contracts to Ritual Chain (id 1979) and
/// wires up quest authorization. Run with:
///   forge script script/Deploy.s.sol:DeployScript --rpc-url ritual --broadcast -vvvv
contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        RitualPassport passport = new RitualPassport();
        console.log("RitualPassport:", address(passport));

        AIOracleQuest aiQuest = new AIOracleQuest(passport);
        console.log("AIOracleQuest:", address(aiQuest));

        HTTPDataQuest httpQuest = new HTTPDataQuest(passport);
        console.log("HTTPDataQuest:", address(httpQuest));

        SchedulerHeartbeatQuest schedulerQuest = new SchedulerHeartbeatQuest(passport);
        console.log("SchedulerHeartbeatQuest:", address(schedulerQuest));

        passport.setQuestAuthorized(address(aiQuest), true);
        passport.setQuestAuthorized(address(httpQuest), true);
        passport.setQuestAuthorized(address(schedulerQuest), true);

        vm.stopBroadcast();

        console.log("\n--- Add these to .env ---");
        console.log("RITUAL_PASSPORT_ADDRESS=", address(passport));
        console.log("AI_ORACLE_QUEST_ADDRESS=", address(aiQuest));
        console.log("HTTP_DATA_QUEST_ADDRESS=", address(httpQuest));
        console.log("SCHEDULER_QUEST_ADDRESS=", address(schedulerQuest));
    }
}
