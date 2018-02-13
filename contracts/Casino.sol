pragma solidity ^0.4.19;

contract Casino {
  // Player information
  address private owner;
  address[] private players;
  address[] private currentPlayers;

  // Game parameters
  uint constant minPlayers = 2;
  uint constant maxPlayers = 6;
  uint constant smallBlindCost = 1 finney;
  uint constant bigBlindCost = 2 finney; // 1000 finney = 1 eth

  // State variables
  bool private playing = false;
  uint private smallBlind = 0; // Index of player paying small blind
  uint private currentPlayer = 0; // Index of player currently betting
  uint private round = 0;
  uint[52] private deck;
  bool private smallBlindPayed = false;
  bool private bigBlindPayed = false;

  function Casino() public {
    owner = msg.sender;
  }

  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  modifier onlySmallBlind() {
    require(msg.sender == players[smallBlind]);
    _;
  }

  modifier onlyBigBlind() {
    require(msg.sender == players[(smallBlind+1)%players.length]);
    _;
  }

  modifier onlyOnceBlindsPayed() {
    require(smallBlindPayed && bigBlindPayed);
    _;
  }

  modifier onlyRound(uint n) {
    require(round == n);
    _;
  }

  modifier costs(uint price) {
    require(msg.value >= price);
    _;
  }

  // Allows a player to request to join the game
  // Could add a cost, paid to the owner
  function joinGame() public {
    if (players.length > maxPlayers || playing)
      revert();

    players.push(msg.sender);
    currentPlayers.push(msg.sender);
  }

  // Leave game functionality?

  // Start the game. Only the owner can start the game
  function startGame() public onlyOwner {
    if (players.length < minPlayers || playing)
      revert();

    playing = true;
    round = 0;

    shuffleCards();
    smallBlind = (smallBlind + 1) % players.length;
    currentPlayer = (smallBlind + 2) % players.length;
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

  function paySmallBlind() public payable
  onlySmallBlind onlyRound(0) costs(smallBlindCost) {

    smallBlindPayed = true;
  }

  function payBigBlind() public payable
  onlyBigBlind onlyRound(0) costs(bigBlindCost) {

    bigBlindPayed = true;
  }

  // can use a mapping to store a bet
  // can use a modifier to make sure we accept bets from the right player
}
