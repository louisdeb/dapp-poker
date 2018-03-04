pragma solidity ^0.4.19;

/* --- Rounds ---
  0: blinds, dealing, initial bets
  1: flop dealt, another round of betting
  2: turn card dealt, another round of betting
  3: river card dealt, final round of betting
  4: showdown: cards revealed & pot distributed
*/

contract Casino {

  struct Hand {
    uint first;
    uint second;
  }

  /* --- Player information --- */
  address public owner;
  address[] private players;
  address[] private currentPlayers;

  // Solidity didn't like declaring 'winners' inside of 'checkWin' because it
  // doesn't have a fixed size. It benefits the programmer to have 'winners'
  // as a dynamic array so that we can pass 'payout' any number of winners.
  address[] private winners;

  /* --- Game parameters --- */
  uint constant minPlayers = 2;
  uint constant maxPlayers = 6;
  uint constant smallBlindCost = 1 finney;
  uint constant bigBlindCost = 2 finney;

  /* --- State variables --- */
  bool private playing = false;

  uint private currentPlayer = 0; // Index of player currently betting
  address private lastPlayerToRaise = 0;

  uint public round = 0; // only public for debug
  uint private maxBet = 0;
  bool private smallBlindPayed = false;
  bool private bigBlindPayed = false;

  uint[52] private deck;
  uint private deckLength = 52;
  bool private dealt = false;

  mapping(address => bool) private inGame; // Whether the player has folded or not
  mapping(address => Hand) private hands;
  mapping(address => uint) private bets;
  uint[] private table; // Cards placed on the table

  /* --- Scoring values --- */
  uint constant private SCORE_ROYAL_FLUSH = 9000;
  uint constant private SCORE_STRAIGHT_FLUSH = 8000;
  uint constant private SCORE_FOUR_OF_A_KIND = 7000;
  uint constant private SCORE_FULL_HOUSE = 6000;
  uint constant private SCORE_FLUSH = 5000;
  uint constant private SCORE_STRAIGHT = 4000;
  uint constant private SCORE_THREE_OF_A_KIND = 3000;
  uint constant private SCORE_TWO_PAIRS = 2000;
  uint constant private SCORE_PAIR = 1000;

  /* mapping(uint => string) private cardNames; // Maps deck indexes to card name */

  // A couple of global variables used to reduce stack size when determining
  // the winner
  uint private firstCard;
  uint private secondCard;

  function Casino() public {
    owner = msg.sender;
    // populateCardNames();
  }

  /* --- Modifiers --- */
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  modifier whenPlaying() {
    require(playing);
    _;
  }

  modifier whenNotPlaying() {
    require(!playing);
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

  /* --- Getters, public & utility --- */
  function getHand() public view whenPlaying returns (uint, uint) {
    uint _first = hands[msg.sender].first;
    uint _second = hands[msg.sender].second;
    return (_first, _second);
    /* return (cardNames[_first], cardNames[_second]); */
  }

  // Can be used to test shuffling but should be removed after that (debug)
  function getDeck() public view whenPlaying returns (uint[52]) {
    return deck;
  }

  function getTableCards() public view whenPlaying returns (uint[]) {
    return table;
    /* uint numCards = table.length;
    string[] memory cards = new string[](numCards);
    for (uint i = 0; i < numCards; i++)
      cards[i] = cardNames[table[i]];
    return cards; */
  }

  function getMaxBet() public view whenPlaying returns (uint) {
    return maxBet;
  }

  function getMyBet() public view whenPlaying returns (uint) {
    return bets[msg.sender];
  }

  function getNumberOfPlayers() public view returns (uint) {
    return players.length;
  }

  function getCurrentPlayers() public view whenPlaying returns (uint, address[]) {
    return (getCurrentPlayer(), getNotFolded());
  }

  function getNotFolded() private view whenPlaying returns (address[]) {
    uint numCurrent = getNumberOfCurrentPlayers();
    address[] memory notFolded = new address[](numCurrent);

    uint n = 0; // tracks current index of notFolded array
    uint totalNum = currentPlayers.length;
    for (uint i = 0; i < totalNum; i++) {
      if (inGame[currentPlayers[i]]) {
        notFolded[n] = currentPlayers[i];
        n++;
      }
    }

    return notFolded;
  }

  // Due to trouble reducing currentPlayer, we use this function to find the
  // correct index of currentPlayer. Even setting currentPlayer to 0 caused issues.
  // currentPlayer shouldn't be read from directly. (Use this function)
  function getCurrentPlayer() private view returns (uint) {
    return currentPlayer % currentPlayers.length;
  }

  // Returns the count of number of players who haven't folded
  function getNumberOfCurrentPlayers() private view returns (uint) {
    uint num = 0;
    for (uint i = 0; i < currentPlayers.length; i++) {
      if (inGame[currentPlayers[i]])
        num++;
    }
    return num;
  }

  /* --- Transactions --- */

  // Allows a player to request to join the game.
  // If the game is full, the player is already a member of the game, or the
  // game is in progress, the call will be rejected.
  function joinGame() public whenNotPlaying {
    if (players.length > maxPlayers || inGame[msg.sender])
      revert();

    players.push(msg.sender);
    currentPlayers.push(msg.sender);
    inGame[msg.sender] = true;
  }

  // Start the game. Only the owner can start the game.
  function startGame() public whenNotPlaying onlyOwner {
    if (players.length < minPlayers)
      revert();

    playing = true;
    round = 0;

    shuffleCards();
    incrementCurrentPlayer();
  }

  // Called by the first player after the dealer to pay in the small blind.
  function paySmallBlind() public payable onlyRound(0)
  whenPlaying onlyCurrentPlayer whenNotDealt costs(smallBlindCost) {
    smallBlindPayed = true;
    setMaxBet(msg.value, msg.sender);
    bets[msg.sender] = msg.value;

    incrementCurrentPlayer();
  }

  // Called by the second player after the dealer to pay in the big blind.
  // Can only be called once the small blind is paid. Paying the big blind
  // results in dealing the hands. Then the first round of betting starts with
  // the player after the big blind.
  function payBigBlind() public payable onlyRound(0)
  whenPlaying onlyCurrentPlayer whenNotDealt costs(bigBlindCost) {
    bigBlindPayed = true;
    setMaxBet(msg.value, msg.sender);
    bets[msg.sender] = msg.value;

    incrementCurrentPlayer();
    deal();
  }

  // Allows the current player to make a bet. If his bet does not match or
  // raise the current max bet, the call will be rejected and he has to play
  // again. If the bet succeedes, the play is passed to the next player and
  // the round may be incremented.
  function makeBet() public payable onlyCurrentPlayer whenPlaying whenDealt {
    uint newBet = bets[msg.sender] + msg.value;
    if(newBet < maxBet)
      revert();

    bets[msg.sender] = newBet;
    setMaxBet(bets[msg.sender], msg.sender);
    incrementCurrentPlayer();
    tryIncrementRound();
  }

  // If the player already matches the max bet, they can check and pass play
  // to the next player.
  function check() public onlyCurrentPlayer whenPlaying {
    if (bets[msg.sender] != maxBet)
      revert();

    incrementCurrentPlayer();
    tryIncrementRound();
  }

  // If the player wants to forfeit their stake, they can fold, removing them
  // from the game.
  function fold() public onlyCurrentPlayer whenDealt whenPlaying {
    inGame[msg.sender] = false;
    incrementCurrentPlayer();

    if (getNumberOfCurrentPlayers() == 1) {
      checkWin();
    } else {
      tryIncrementRound();
    }
  }

  /* --- Private Utility Functions --- */

  // If the passed bet is greater than the max bet, raise the max bet and
  // set the last player to raise.
  function setMaxBet(uint bet, address sender) private {
    if (bet > maxBet) {
        maxBet = bet;
        lastPlayerToRaise = sender;
    }
  }

  // Load a deck of cards & shuffle it
  function shuffleCards() private {
    for (uint i = 0; i < deckLength; i++)
      deck[i] = i;

    // uint _deckLength = deckLength;
    // for (uint j = 0; j < _deckLength; j++) {
    //   uint randomNumber = uint(block.blockhash(block.number-1)) % deckLength;
    //   uint a = deck[j];
    //   uint b = deck[randomNumber];
    //   deck[j] = b;
    //   deck[randomNumber] = a;
    // }
  }

  // Pass a card to each player in turn, and then another card.
  function deal() private onlyRound(0)
  onlyOnceBlindsPayed whenPlaying whenNotDealt {
    dealt = true;
    uint numPlayers = players.length;
    for(uint i=0; i < numPlayers; i++) {
      hands[players[i]].first = drawCard();
    }
    for(uint j=0; j < numPlayers; j++) {
      hands[players[j]].second = drawCard();
    }
  }

  // Draw a card from the top of the deck and return it.
  function drawCard() private returns (uint) {
    uint card = deck[deckLength-1];
    deckLength--;
    return card;
  }

  // Increment current player counter to the next non-folded player.
  function incrementCurrentPlayer() private {
    currentPlayer++;
    if (!inGame[currentPlayers[getCurrentPlayer()]])
      incrementCurrentPlayer();
  }

  // Increment the round if all players have had the chance to raise or have
  // called the max bet.
  function tryIncrementRound() private {
    // Make sure all players have had the chance to bet
    address currentPlayerAddress = currentPlayers[getCurrentPlayer()];
    if (currentPlayerAddress == lastPlayerToRaise &&
        bets[currentPlayerAddress] == maxBet) {

      // Check all bets are equal
      bool mismatch = false;
      for (uint i = 1; i < currentPlayers.length; i++) {
        address playerAddress = currentPlayers[i];

        // Don't bother if the player has folded
        if (!inGame[playerAddress])
          continue;

        if (bets[playerAddress] != maxBet) {
          mismatch = true;
          break;
        }
      }

      // If all bets are maxBet
      if (!mismatch) {
        // Increment round
        round++;

        // Either play table cards or go to the showdown
        if (round < 4) {
          playTableCards();
        } else {
          checkWin();
        }
      }
    }
  }

  // Draw cards from the deck and place them on the table (to represent the
  // flop etc.).
  function playTableCards() private whenPlaying {
    if (round == 1) {
      for (uint i = 0; i < 3; i++)
        table.push(drawCard());
    } else {
      table.push(drawCard());
    }
  }

  // End game logic to check for winners and to pay them.
  function checkWin() whenPlaying private {
    // If 1 player remains, they win.
    if (getNumberOfCurrentPlayers() == 1) {
      // Get address of remaining players
      address winner = getNotFolded()[0];
      winners.push(winner);
      payout();
    } else {
      // revealHands();
      determineWinners();
      payout();
    }
    playing = false;
  }

  // Pay winners their share of the pot.
  function payout() private {
    uint numWinners = winners.length;
    uint prize = this.balance / numWinners;

    for (uint i = 0; i < numWinners; i++) {
      address winner = winners[i];
      winner.transfer(prize);
    }

    if (this.balance > 0)
      owner.transfer(this.balance);
  }

  /* --- Poker Winning Logic --- */

  // Get score for each winner and work out who deserves the pot
  function determineWinners() private {
    address[] memory _currentPlayers = getNotFolded();
    uint n = _currentPlayers.length;
    uint[] memory scores = new uint[](n);

    for (uint i = 0; i < n; i++)
      scores[i] = determineScore(_currentPlayers[i]);

    address winner;
    uint maxScore = scores[0];

    for (uint j = 1; j < n; j++) {
      if (scores[j] > maxScore) {
        winner = _currentPlayers[j];
        maxScore = scores[j];
      }
    }

    bool drawCondition = false;

    for (uint k = 0; k < n; k++) {
      if (scores[k] == maxScore && winner != _currentPlayers[k]) {
        drawCondition = true;
        break;
      }
    }

    if (drawCondition) {
      uint m = 0; // Track winners index
      for (uint l = 0; l < n; l++) { // Find and add multiple winners
        if (scores[l] == maxScore) {
          winners[m] = _currentPlayers[l];
          m++;
        }
      }
    } else {
      winners[0] = winner; // Take the player with the max score.
    }
  }

  // Get score for a player (which represents how valuable their hand is).
  function determineScore(address player) private returns (uint) {
    Hand memory hand = hands[player];
    firstCard = hand.first;
    secondCard = hand.second;

    uint score = 0;

    if (hasRoyalFlush()) {
      score = SCORE_ROYAL_FLUSH;
    } else if (hasStraightFlush() != 0) {
      score = SCORE_STRAIGHT_FLUSH + hasStraightFlush();
    } else if (hasFourOfAKind() != 0) {
      score = SCORE_FOUR_OF_A_KIND + hasFourOfAKind();
    } else if (hasFullHouse() != 0) {
      score = SCORE_FULL_HOUSE + hasFullHouse();
    } else if (hasFlush()) {
      score = SCORE_FLUSH;
    } else if (hasStraight() != 0) {
      score = SCORE_STRAIGHT + hasStraight();
    } else if (hasThreeOfAKind() != 0) {
      score = SCORE_THREE_OF_A_KIND + hasThreeOfAKind();
    // } else if (hasTwoPair() != 0) {
    //   score = SCORE_TWO_PAIRS + hasTwoPair();
    } else if (hasPair() != 0) {
      score = SCORE_PAIR + hasPair();
    }
    // This used to be a very heavily nested if-else statement that had the
    // optimisation where each check function, which may be computationally
    // heavy, was only called once. However it resulted in a stack too deep
    // exception. The optimisation is sacrificed here, to avoid the exception,
    // and we have to call each check twice.
    // This is a memory-time trade off where we have opted to optimise memory.

    // Add on the high card value to their score, in case two scores are equal
    // and the winner is determined by the high card.
    score = score + highCardScore();

    return score;
  }

  function hasRoyalFlush() private view returns (bool) {
    return
    // first suit
    tableOrHandContains(8)  && tableOrHandContains(9)  &&
    tableOrHandContains(10) && tableOrHandContains(11) &&
    tableOrHandContains(12) ||
    // second suit
    tableOrHandContains(21) && tableOrHandContains(22) &&
    tableOrHandContains(23) && tableOrHandContains(24) &&
    tableOrHandContains(25) ||
    // third suit
    tableOrHandContains(34) && tableOrHandContains(35) &&
    tableOrHandContains(36) && tableOrHandContains(37) &&
    tableOrHandContains(38) ||
    // fourth suit
    tableOrHandContains(47) && tableOrHandContains(48) &&
    tableOrHandContains(49) && tableOrHandContains(50) &&
    tableOrHandContains(51);
  }

  function hasStraightFlush() private view returns (uint) {
    for (uint j = 0; j < 51; j += 13) {
      // This inner loop could be optimised...
      for (uint i = j; i < j+7; i++) {
        if (tableOrHandContains(i)   &&
            tableOrHandContains(i+1) &&
            tableOrHandContains(i+2) &&
            tableOrHandContains(i+3) &&
            tableOrHandContains(i+4))
          return i+4;
      }
    }
    return 0;
  }

  function hasFourOfAKind() private view returns (uint) {
    for (uint i = 0; i < 13; i++) {
      if (tableOrHandContains(i)    &&
          tableOrHandContains(i+13) &&
          tableOrHandContains(i+26) &&
          tableOrHandContains(i+39))
        return i+1;
    }
    return 0;
  }

  function hasFullHouse() private view returns (uint) {
    uint threeOfAKind = hasThreeOfAKind();
    uint pair = hasPair();
    if ((threeOfAKind != 0) && (pair != 0) && (threeOfAKind != pair))
      return threeOfAKind*13 + pair; // logic ensuring QQQ99 beats 999QQ
    return 0;
  }

  function hasFlush() private view returns (bool) {
    uint n = 0; // Number of cards within suit

    // For every suit
    for (uint i = 0; i < 52; i += 13) {
      n = 0;
      if (firstCard >= i && firstCard <= i+12)
        n++;
      if (secondCard >= i && secondCard <= i+12)
        n++;

      uint numTableCards = table.length;
      for (uint j = 0; j < numTableCards; j++) {
        uint card = table[j];
        if (card >= i && card <= i+12)
          n++;
      }

      if (n >= 5)
        break;
    }

    return (n >= 5); // High card will determine between two flushes
  }

  function hasStraight() private view returns (uint) {
    for (uint i = 0; i < 9; i++) {
      if (tableOrHandContainsMod(i)   &&
          tableOrHandContainsMod(i+1) &&
          tableOrHandContainsMod(i+2) &&
          tableOrHandContainsMod(i+3) &&
          tableOrHandContainsMod(i+4))
        return i+4;
    }
    return 0;
  }

  function hasThreeOfAKind() private view returns (uint) {
    for (uint i = 0; i < 13; i++) {
      bool _first = tableOrHandContains(i);
      bool _second = tableOrHandContains(i+13);
      bool _third = tableOrHandContains(i+26);
      bool _fourth = tableOrHandContains(i+39);
      if (_first  && _second && _third  ||
          _first  && _second && _fourth ||
          _second && _third && _fourth)
        return i+1;
    }
    return 0;
  }

  function hasTwoPair() private view returns (uint) {
    uint firstPair = hasPair();
    if (firstPair == 0)
      return 0;

    // actual value of first pair is (firstPair - 1)

    uint secondPair = 0;
    for (uint i = 0; i < firstPair-1; i++) {
      bool _first = tableOrHandContains(i);
      bool _second = tableOrHandContains(i+13);
      bool _third = tableOrHandContains(i+26);
      bool _fourth = tableOrHandContains(i+39);
      if (_first && _second || _first && _third || _first && _fourth ||
          _second && _third || _second && _fourth || _third && _fourth)
        secondPair = i+1;
    }

    for (uint j = firstPair; j < 13; j++) {
      bool __first = tableOrHandContains(j);
      bool __second = tableOrHandContains(j+13);
      bool __third = tableOrHandContains(j+26);
      bool __fourth = tableOrHandContains(j+39);
      if (__first && __second || __first && __third || __first && __fourth ||
          __second && __third || __second && __fourth || __third && __fourth)
        secondPair = j+1;
    }

    return (secondPair != 0) ? secondPair*13 + firstPair : 0;
  }

  function hasPair() private view returns (uint) {
    for (uint i = 0; i < 13; i++) {
      bool _first = tableOrHandContains(i);
      bool _second = tableOrHandContains(i+13);
      bool _third = tableOrHandContains(i+26);
      bool _fourth = tableOrHandContains(i+39);
      if (_first && _second || _first && _third || _first && _fourth ||
          _second && _third || _second && _fourth || _third && _fourth)
        return i+1;
    }
    return 0;
  }

  function highCardScore() private view returns (uint) {
    return (firstCard > secondCard) ? firstCard : secondCard;
  }

  function tableOrHandContains(uint n)
  private view returns (bool) {
    return tableContains(n) || handContains(n);
  }

  function tableContains(uint n) private view returns (bool) {
    for (uint i = 0; i < table.length; i++) {
      if (table[i] == n)
        return true;
    }
    return false;
  }

  function handContains(uint n) private view returns (bool) {
    return n == firstCard || n == secondCard;
  }

  function tableOrHandContainsMod(uint n) private view returns (bool) {
    return tableContainsMod(n) || handContainsMod(n);
  }

  function tableContainsMod(uint n) private view returns (bool) {
    for (uint i = 0; i < table.length; i++) {
      if (table[i]%13 == n)
        return true;
    }
    return false;
  }

  function handContainsMod(uint n) private view returns (bool) {
    return n == (firstCard%13) || n == (secondCard%13);
  }

  /*
  function populateCardNames() private {
    cardNames[0] = "2C";
    cardNames[1] = "3C";
    cardNames[2] = "4C";
    cardNames[3] = "5C";
    cardNames[4] = "6C";
    cardNames[5] = "7C";
    cardNames[6] = "8C";
    cardNames[7] = "9C";
    cardNames[8] = "10C";
    cardNames[9] = "JC";
    cardNames[10] = "QC";
    cardNames[11] = "KC";
    cardNames[12] = "AC";

    cardNames[13] = "2S";
    cardNames[14] = "3S";
    cardNames[15] = "4S";
    cardNames[16] = "5S";
    cardNames[17] = "6S";
    cardNames[18] = "7S";
    cardNames[19] = "8S";
    cardNames[20] = "9S";
    cardNames[21] = "10S";
    cardNames[22] = "JS";
    cardNames[23] = "QS";
    cardNames[24] = "KS";
    cardNames[25] = "AS";

    cardNames[26] = "2H";
    cardNames[27] = "3H";
    cardNames[28] = "4H";
    cardNames[29] = "5H";
    cardNames[30] = "6H";
    cardNames[31] = "7H";
    cardNames[32] = "8H";
    cardNames[33] = "9H";
    cardNames[34] = "10H";
    cardNames[35] = "JH";
    cardNames[36] = "QH";
    cardNames[37] = "KH";
    cardNames[38] = "AH";

    cardNames[39] = "2D";
    cardNames[40] = "3D";
    cardNames[41] = "4D";
    cardNames[42] = "5D";
    cardNames[43] = "6D";
    cardNames[44] = "7D";
    cardNames[45] = "8D";
    cardNames[46] = "9D";
    cardNames[47] = "10D";
    cardNames[48] = "JD";
    cardNames[49] = "QD";
    cardNames[50] = "KD";
    cardNames[51] = "AD";
  */

}
