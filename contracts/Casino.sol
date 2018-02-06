pragma solidity ^0.4.0;

contract Casino {
    uint constant minPlayers = 2;
    uint constant maxPlayers = 6;
    address[] playerAddresses;
    bool playing = false;

    function joinGame(address playerAddress) public {
        if (playerAddresses.length < maxPlayers && !playing) {
            playerAddresses.push(playerAddress);
            if (playerAddresses.length > minPlayers)
                // Could add some 'vote ready' functionality to wait for more players.
                // Currently will just wait till we have 2 players.
                playGame();
        }
    }

    function playGame() private {
        playing = true;
    }
}
