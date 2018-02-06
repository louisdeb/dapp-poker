pragma solidity ^0.4.19;

contract Dealer {
    // Shuffled contains the shuffled deck of cards.
    // To prevent cheating, this variable should be encrypted. We can encrypt it
    // before being returned from `shuffle`. Since `shuffle` is `pure`, this
    // should work well (?).
    uint[52] shuffled;

    function Dealer() public {
        shuffleCards();
    }

    function shuffleCards() private {
        uint[52] memory cards;
        for(uint i = 0; i < 52; i++)
            cards[i] = i;

        shuffled = shuffle(cards);
    }

    function shuffle(uint[52] deck) private pure returns (uint[52]) {
        for (var i = deck.length - 1; i > 0; i--) {
            uint random_number = 1;
            // Old implementation: uint(block.blockhash(block.number-1))%10 + 1;
            // To be refined.

            uint j = random_number * (i + 1);
            uint temp = deck[i];
            deck[i] = deck[j];
            deck[j] = temp;
        }

        return deck;
    }
}
