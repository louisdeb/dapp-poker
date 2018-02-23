pragma solidity ^0.4.19;

contract Casino {

  struct Hand {
      uint first;
      uint second;
  }

  // Player information
  address public owner;
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
  uint private deckLength = 52;
  bool private smallBlindPayed = false;
  bool private bigBlindPayed = false;

  mapping(address => Hand) private hands;

  function Casino() public {
    owner = msg.sender;
  }

  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  modifier whenPlaying() {
    require(playing);
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

  // ROUNDS
  // 0: blinds, dealing, initial bets
  // 1: flop dealt, another round of betting
  // 2: turn card dealt, another round of betting
  // 3: river card dealt, final round of betting
  // 4: showdown: cards revealed & pot distributed ... blinds rotated

  // Load a deck of cards & shuffle it
  // NB: Shuffling not implemented due to infinite loop possibility
  function shuffleCards() private {
    // Great shuffling
    deck = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51];
  }

  function paySmallBlind() public payable
  onlySmallBlind onlyRound(0) whenPlaying costs(smallBlindCost) {
    smallBlindPayed = true;
    if(bigBlindPayed)
        deal();
  }

  function payBigBlind() public payable
  onlyBigBlind onlyRound(0) whenPlaying costs(bigBlindCost) {
    bigBlindPayed = true;
    if(smallBlindPayed)
        deal();
  }

  function deal() private onlyRound(0) onlyOnceBlindsPayed {
      uint numPlayers = players.length;
      for(uint i=0; i < numPlayers; i++) {
        hands[players[i]].first = drawCard();
      }
      for(uint j=0; j < numPlayers; j++) {
        hands[players[j]].second = drawCard();
      }
  }

  function drawCard() private returns (uint) {
      uint card = deck[deckLength-1];
      deckLength--;
      return card;
  }

  function getHand() public view whenPlaying returns (uint, uint) {
    return (hands[msg.sender].first, hands[msg.sender].second);
  }

  // Can be used to test shuffling but should be removed after that
  function getDeck() public view whenPlaying returns (uint[52]) {
    return deck;
  }

  // can use a mapping to store a bet
  // can use a modifier to make sure we accept bets from the right player
}
