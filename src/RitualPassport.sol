// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title RitualPassport
/// @notice Soulbound (non-transferable) badge NFT. Authorized quest contracts grant badges
/// as users complete on-chain interactions with Ritual precompiles. Intended as a portable,
/// on-chain-readable record of testnet engagement (e.g. for Discord-role or airdrop checks
/// built independently on top of this contract).
contract RitualPassport is ERC721, Ownable {
    using Strings for uint256;

    uint8 public constant BADGE_AI_ORACLE = 1 << 0;
    uint8 public constant BADGE_HTTP_DATA = 1 << 1;
    uint8 public constant BADGE_SCHEDULER = 1 << 2;
    uint8 public constant ALL_BADGES = BADGE_AI_ORACLE | BADGE_HTTP_DATA | BADGE_SCHEDULER;

    uint256 private _nextTokenId = 1;

    mapping(address user => uint256 tokenId) public tokenIdOf;
    mapping(address user => uint8 badges) public badgesOf;
    mapping(address quest => bool authorized) public isQuest;

    event QuestAuthorized(address indexed quest, bool authorized);
    event BadgeGranted(address indexed user, uint8 badge, uint8 newBadges);

    modifier onlyQuest() {
        require(isQuest[msg.sender], "RitualPassport: not authorized quest");
        _;
    }

    constructor() ERC721("Ritual Passport", "RITUALPASS") Ownable(msg.sender) {}

    function setQuestAuthorized(address quest, bool authorized) external onlyOwner {
        isQuest[quest] = authorized;
        emit QuestAuthorized(quest, authorized);
    }

    /// @notice Called by an authorized quest contract when a user completes that quest.
    /// Idempotent — re-granting an already-held badge is a no-op.
    function grantBadge(address user, uint8 badge) external onlyQuest {
        uint8 current = badgesOf[user];
        uint8 updated = current | badge;
        if (updated == current) return;

        if (tokenIdOf[user] == 0) {
            uint256 tokenId = _nextTokenId++;
            tokenIdOf[user] = tokenId;
            _safeMint(user, tokenId);
        }
        badgesOf[user] = updated;
        emit BadgeGranted(user, badge, updated);
    }

    function hasBadge(address user, uint8 badge) external view returns (bool) {
        return badgesOf[user] & badge == badge;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        address user = ownerOf(tokenId);
        uint8 badges = badgesOf[user];

        string memory json = string.concat(
            '{"name":"Ritual Passport #',
            tokenId.toString(),
            '","description":"Soulbound proof-of-quest badge for the Ritual Chain testnet.",',
            '"attributes":[{"trait_type":"Badges Earned","value":"',
            _badgeNames(badges),
            '"},{"trait_type":"Badge Count","value":',
            _badgeCount(badges).toString(),
            "}]}"
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function _badgeCount(uint8 badges) internal pure returns (uint256 count) {
        if (badges & BADGE_AI_ORACLE != 0) count++;
        if (badges & BADGE_HTTP_DATA != 0) count++;
        if (badges & BADGE_SCHEDULER != 0) count++;
    }

    function _badgeNames(uint8 badges) internal pure returns (string memory) {
        if (badges == 0) return "None";

        string memory names = "";
        bool first = true;
        if (badges & BADGE_AI_ORACLE != 0) {
            names = "AI Oracle";
            first = false;
        }
        if (badges & BADGE_HTTP_DATA != 0) {
            names = first ? "HTTP Data" : string.concat(names, ", HTTP Data");
            first = false;
        }
        if (badges & BADGE_SCHEDULER != 0) {
            names = first ? "Scheduler" : string.concat(names, ", Scheduler");
        }
        return names;
    }

    /// @dev Soulbound: allow mint (`from == 0`) and burn (`to == 0`), block transfers.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            revert("RitualPassport: soulbound, non-transferable");
        }
        return super._update(to, tokenId, auth);
    }
}
