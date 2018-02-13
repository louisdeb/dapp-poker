pragma solidity ^0.4.19;

contract Casino {
  // Player information
  address private owner;
  address[] private players;

  // Game parameters
  uint constant minPlayers = 2;
  uint constant maxPlayers = 6;

  // State variables
  bool private playing = false;
  uint private turn = 0;
  uint[52] private deck;

  function Casino() public {
    owner = msg.sender;
  }

  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  // Allows a player to request to join the game
  function joinGame() public {
    if (players.length > maxPlayers || playing)
      revert();

    players.push(msg.sender);
  }

  // Leave game functionality?

  // Start the game. Only the owner can start the game
  function startGame() public onlyOwner {
    if (players.length < minPlayers || playing)
      revert();

    playing = true;
    shuffleCards();
  }

  // 0: blinds, dealing, initial bets
  // 1: flop dealt, another round of betting
  // 2: turn card dealt, another round of betting
  // 3: river card dealt, final round of betting
  // 4: showdown: cards revealed & pot distributed ... blinds rotated

  // Load a deck of cards & shuffle it
  function shuffleCards() private {
    uint[52] memory cards;
    for(uint i = 0; i < 52; i++)
      cards[i] = i;

    deck = shuffle(cards);
  }

  function shuffle(uint[52] cards) private pure returns (uint[52]) {
    for (var i = cards.length - 1; i > 0; i--) {
      uint random_number = 1;
      // Old implementation: uint(block.blockhash(block.number-1))%10 + 1;
      // To be refined.

      uint j = random_number * (i + 1);
      uint temp = cards[i];
      cards[i] = cards[j];
      cards[j] = temp;
    }

    return cards;
  }

  // can use a mapping to store a bet
  // can use a modifier to make sure we accept bets from the right player
}
