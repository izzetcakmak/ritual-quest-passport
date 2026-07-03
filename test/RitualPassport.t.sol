// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RitualPassport} from "../src/RitualPassport.sol";

contract RitualPassportTest is Test {
    RitualPassport passport;
    address owner = address(this);
    address quest = makeAddr("quest");
    address user = makeAddr("user");

    function setUp() public {
        passport = new RitualPassport();
        passport.setQuestAuthorized(quest, true);
    }

    function test_OnlyAuthorizedQuestCanGrantBadge() public {
        uint8 badge = passport.BADGE_AI_ORACLE();

        vm.prank(makeAddr("randomCaller"));
        vm.expectRevert("RitualPassport: not authorized quest");
        passport.grantBadge(user, badge);
    }

    function test_GrantBadge_MintsTokenOnFirstBadge() public {
        uint8 badge = passport.BADGE_AI_ORACLE();

        vm.prank(quest);
        passport.grantBadge(user, badge);

        assertEq(passport.balanceOf(user), 1);
        assertEq(passport.ownerOf(passport.tokenIdOf(user)), user);
        assertTrue(passport.hasBadge(user, badge));
        assertFalse(passport.hasBadge(user, passport.BADGE_HTTP_DATA()));
    }

    function test_GrantBadge_AccumulatesWithoutReminting() public {
        vm.startPrank(quest);
        passport.grantBadge(user, passport.BADGE_AI_ORACLE());
        uint256 tokenId = passport.tokenIdOf(user);

        passport.grantBadge(user, passport.BADGE_HTTP_DATA());
        vm.stopPrank();

        assertEq(passport.balanceOf(user), 1);
        assertEq(passport.tokenIdOf(user), tokenId);
        assertEq(passport.badgesOf(user), passport.BADGE_AI_ORACLE() | passport.BADGE_HTTP_DATA());
    }

    function test_GrantBadge_IdempotentReGrant() public {
        vm.startPrank(quest);
        passport.grantBadge(user, passport.BADGE_AI_ORACLE());
        passport.grantBadge(user, passport.BADGE_AI_ORACLE());
        vm.stopPrank();

        assertEq(passport.balanceOf(user), 1);
        assertEq(passport.badgesOf(user), passport.BADGE_AI_ORACLE());
    }

    function test_Soulbound_TransferReverts() public {
        uint8 badge = passport.BADGE_AI_ORACLE();

        vm.prank(quest);
        passport.grantBadge(user, badge);
        uint256 tokenId = passport.tokenIdOf(user);

        vm.prank(user);
        vm.expectRevert("RitualPassport: soulbound, non-transferable");
        passport.transferFrom(user, makeAddr("other"), tokenId);
    }

    function test_TokenURI_ReflectsAllBadges() public {
        vm.startPrank(quest);
        passport.grantBadge(user, passport.BADGE_AI_ORACLE());
        passport.grantBadge(user, passport.BADGE_HTTP_DATA());
        passport.grantBadge(user, passport.BADGE_SCHEDULER());
        vm.stopPrank();

        string memory uri = passport.tokenURI(passport.tokenIdOf(user));
        assertTrue(bytes(uri).length > 0);
    }

    function test_OnlyOwnerCanAuthorizeQuest() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert();
        passport.setQuestAuthorized(makeAddr("newQuest"), true);
    }
}
