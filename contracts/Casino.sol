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
  address private lastPlayerToRaise = 0;
  uint private maxBet = 0;
  uint public round = 0; // only public for debug
  uint[52] private deck;
  uint private deckLength = 52;
  bool private smallBlindPayed = false;
  bool private bigBlindPayed = false;
  bool private dealt = false;

  mapping(address => Hand) private hands;
  mapping(address => uint) private bets;
  uint[] private table;

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

  function getTableCards() public view whenPlaying returns (uint[]) {
      return table;
  }

  function getMaxBet() public view whenPlaying returns (uint) {
      return maxBet;
  }

  function getMyBet() public view whenPlaying returns (uint) {
      return bets[msg.sender];
  }

  function getNumberOfPlayers() public view returns (uint) {
      return currentPlayers.length;
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
    currentPlayers.push(msg.sender);
  }

  // Start the game. Only the owner can start the game
  function startGame() public onlyOwner {
    if (players.length < minPlayers || playing)
      revert();

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

  function paySmallBlind() public payable onlyRound(0)
  whenPlaying whenNotDealt costs(smallBlindCost) {
    if (currentPlayers[getCurrentPlayer()] != msg.sender)
      revert();

    smallBlindPayed = true;
    setMaxBet(msg.value, msg.sender);
    bets[msg.sender] = msg.value;

    incrementCurrentPlayer();
  }

  function payBigBlind() public payable onlyRound(0)
  whenPlaying costs(bigBlindCost) {
    if (currentPlayers[getCurrentPlayer()] != msg.sender || dealt)
      revert();

    bigBlindPayed = true;
    setMaxBet(msg.value, msg.sender);
    bets[msg.sender] = msg.value;

    incrementCurrentPlayer();
    deal();
  }

  function setMaxBet(uint bet, address sender) private {
    if (bet > maxBet) {
        maxBet = bet;
        lastPlayerToRaise = sender;
    }
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

  function makeBet() public payable whenPlaying whenDealt {
    uint newBet = bets[msg.sender] + msg.value;
    if(newBet < maxBet ||
       currentPlayers[getCurrentPlayer()] != msg.sender)
      revert();

    bets[msg.sender] = newBet;
    setMaxBet(bets[msg.sender], msg.sender);
    incrementCurrentPlayer();
    tryIncrementRound();
  }

  // Has trouble being reduced
  function incrementCurrentPlayer() private {
    currentPlayer++;
  }

  function tryIncrementRound() private {
    // Make sure all players have had the chance to bet
    address currentPlayerAddress = currentPlayers[getCurrentPlayer()];
    if (currentPlayerAddress == lastPlayerToRaise &&
        bets[currentPlayerAddress] == maxBet) {

      // Check all bets are equal
      bool mismatch = false;
      uint numCurrentPlayers = currentPlayers.length;
      for (uint i=1; i < numCurrentPlayers; i++) {
        if (bets[currentPlayers[i]] != maxBet) {
          mismatch = true;
          break;
        }
      }

      // If all bets are maxBet
      if (!mismatch) {
        // Increment round
        round++;

        if (round < 4) {
          playTableCards();
        } else {
          checkWin();
        }
      }
    }
  }

  function playTableCards() private whenPlaying {
    if (round == 1) {
      for (uint i = 0; i < 3; i++)
        table.push(drawCard());
    } else {
      table.push(drawCard());
    }
  }

  function check() public onlyCurrentPlayer whenPlaying {
    if (bets[msg.sender] != maxBet)
      revert();

    incrementCurrentPlayer();
    tryIncrementRound();
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
    } // naturally increments the current player

    if (currentPlayers.length == 1) {
      checkWin();
      return;
    }

    tryIncrementRound();
  }

  function checkWin() private whenPlaying {
    if (currentPlayers.length == 1) {
      // win for the final player
    }

    // otherwise reveal hands & determine winner
  }

}
