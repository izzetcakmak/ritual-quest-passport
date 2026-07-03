// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RitualAddresses} from "../RitualAddresses.sol";
import {RitualPassport} from "../RitualPassport.sol";

/// @title HTTPDataQuest
/// @notice Quest #2: fetch external data through Ritual's HTTP Call precompile (0x0801). A
/// settled 2xx response with no executor error grants the HTTP_DATA badge.
/// @dev The 13-field HTTP Call request must be ABI-encoded off-chain (see the `ritual-dapp-http`
/// skill for the exact field layout / executor discovery) and passed in as raw `httpInput`
/// bytes.
contract HTTPDataQuest {
    RitualPassport public immutable PASSPORT;

    event DataFetched(address indexed user, uint16 statusCode, string errorMessage);
    event QuestCompleted(address indexed user);

    constructor(RitualPassport passport) {
        PASSPORT = passport;
    }

    function fetchData(bytes calldata httpInput) external returns (uint16 statusCode, string memory errorMessage) {
        (bool ok, bytes memory rawOutput) = RitualAddresses.HTTP_PRECOMPILE.call(httpInput);
        require(ok, "HTTPDataQuest: precompile call failed");

        // Short-running async envelope: (bytes simmedInput, bytes actualOutput).
        (, bytes memory actualOutput) = abi.decode(rawOutput, (bytes, bytes));
        require(actualOutput.length > 0, "HTTPDataQuest: not settled yet (submit a real tx, not eth_call)");

        bytes memory body;
        (statusCode,,, body, errorMessage) = abi.decode(actualOutput, (uint16, string[], string[], bytes, string));

        emit DataFetched(msg.sender, statusCode, errorMessage);

        if (statusCode >= 200 && statusCode < 300 && bytes(errorMessage).length == 0) {
            PASSPORT.grantBadge(msg.sender, PASSPORT.BADGE_HTTP_DATA());
            emit QuestCompleted(msg.sender);
        }
    }
}
