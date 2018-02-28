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
  uint constant bigBlindCost = 2 finney;

  // State variables
  bool private playing = false;
  uint private currentPlayer = 0; // Index of player currently betting
  uint private maxBet = 0;
  uint private round = 0;
  uint[52] private deck;
  uint private deckLength = 52;
  bool private smallBlindPayed = false;
  bool private bigBlindPayed = false;
  bool private dealt = false;

  mapping(address => Hand) private hands;
  mapping(address => uint) private bets;

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

  modifier whenNotDealt() {
      require(!dealt);
      _;
  }

  modifier whenDealt() {
      require(dealt);
      _;
  }

  modifier onlyOnceBlindsPayed() {
    require(smallBlindPayed && bigBlindPayed);
    _;
  }

  modifier onlyCurrentPlayer() {
      require(msg.sender == currentPlayers[getCurrentPlayer()]);
      _;
  }

  modifier onlyRound(uint n) {
    require(round == n);
    _;
  }

  modifier costs(uint price) {
    require(msg.value == price);
    _;
  }

  function getHand() public view whenPlaying returns (uint, uint) {
    return (hands[msg.sender].first, hands[msg.sender].second);
  }

  // Can be used to test shuffling but should be removed after that
  function getDeck() public view whenPlaying returns (uint[52]) {
    return deck;
  }

  function getMaxBet() public view whenPlaying returns (uint) {
      return maxBet;
  }

  function getMyBet() public view whenPlaying returns (uint) {
      return bets[msg.sender];
  }

  function getCurrentPlayers() public view whenPlaying returns (uint, address[]) {
      return (getCurrentPlayer(), currentPlayers);
  }

  // Due to trouble reducing currentPlayer, we use this function to find the
  // correct index of currentPlayer.
  // currentPlayer shouldn't be read from directly. (Use this function)
  function getCurrentPlayer() private view returns (uint) {
      return currentPlayer % currentPlayers.length;
  }

  // Allows a player to request to join the game
  // Could add a cost, paid to the owner
  function joinGame() public {
    if (players.length > maxPlayers || playing)
      revert();

    players.push(msg.sender);
  }

  // Start the game. Only the owner can start the game
  function startGame() public onlyOwner {
    if (players.length < minPlayers || playing)
      revert();

    uint numPlayers = players.length;
    for (uint i = 0; i < numPlayers; i++)
      currentPlayers.push(players[i]);

    playing = true;
    round = 0;

    shuffleCards();
    incrementCurrentPlayer();
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

  function paySmallBlind() public payable onlyCurrentPlayer onlyRound(0)
  whenPlaying whenNotDealt costs(smallBlindCost) {
    smallBlindPayed = true;
    setMaxBet(msg.value);
    bets[msg.sender] = msg.value;

    incrementCurrentPlayer();
  }

  function payBigBlind() public payable onlyCurrentPlayer onlyRound(0)
  whenPlaying whenNotDealt costs(bigBlindCost) {
    bigBlindPayed = true;
    setMaxBet(msg.value);
    bets[msg.sender] = msg.value;

    incrementCurrentPlayer();
    deal();
  }

  function setMaxBet(uint bet) private {
      maxBet = bet > maxBet ? bet : maxBet;
  }

  function deal() private onlyRound(0) onlyOnceBlindsPayed whenNotDealt {
    dealt = true;
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

  function makeBet() public payable onlyCurrentPlayer whenPlaying whenDealt {
    uint currentBet = bets[msg.sender];
    if(currentBet + msg.value < maxBet)
      revert();

    bets[msg.sender] = currentBet + msg.value;
    setMaxBet(bets[msg.sender]);
    incrementCurrentPlayer();
    tryIncrementRound();
  }

  // Has trouble being reduced
  function incrementCurrentPlayer() private {
    currentPlayer++;
  }

  function tryIncrementRound() private {
    uint previousBet = bets[currentPlayers[0]];
    bool mismatch = false;

    uint numCurrentPlayers = currentPlayers.length;
    for (uint i=1; i < numCurrentPlayers; i++) {
      uint playerBet = bets[currentPlayers[i]];
      if (previousBet != playerBet) {
        mismatch = true;
        break;
      }
      previousBet = playerBet;
    }

    // has a problem when first player checks but another player wants to bet
    if (!mismatch) {
      round++;
      // deal another card or whatever
    }
  }

  function check() public onlyCurrentPlayer whenPlaying {
    if (bets[msg.sender] != maxBet)
      revert();

    incrementCurrentPlayer();
  }

  function fold() public onlyCurrentPlayer onlyOnceBlindsPayed whenPlaying {
    uint i = 0;
    uint numCurrentPlayers = currentPlayers.length;
    for (i; i < numCurrentPlayers; i++) {
      if (currentPlayers[i] == msg.sender) {
        for (uint j=i; j < numCurrentPlayers-1; j++) {
          currentPlayers[i] = currentPlayers[i+1];
        }

        delete currentPlayers[numCurrentPlayers-1];
        numCurrentPlayers--;
        break;
      }
    }

    checkWin();
  }

  function checkWin() private whenPlaying {
      if (currentPlayers.length == 1) {
          // win for the final player
      }

      // otherwise reveal hands & determine winner
  }

}
