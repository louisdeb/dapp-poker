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

  function Casino() public {
    owner = msg.sender;
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
    return (hands[msg.sender].first, hands[msg.sender].second);
  }

  // Can be used to test shuffling but should be removed after that (debug)
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
  // NB: Shuffling not implemented due to infinite loop possibility
  function shuffleCards() private {
    // Great shuffling
    deck = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51];
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
      for (uint i=1; i < currentPlayers.length; i++) {
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
  function determineScore(address player) private view returns (uint) {
    uint score = 0;
    Hand memory hand = hands[player];
    uint firstCard = hand.first;
    uint secondCard = hand.second;

    if (hasRoyalFlush(firstCard, secondCard)) {
      score = SCORE_ROYAL_FLUSH;
    } else {
      score = hasStraightFlush(firstCard, secondCard);
      if (score != 0) {
        score = SCORE_STRAIGHT_FLUSH + score;
      } else {
        score = hasFourOfAKind(firstCard, secondCard);
        if (score != 0) {
          score = SCORE_FOUR_OF_A_KIND + score;
        } else {
          score = hasFullHouse(firstCard, secondCard);
          if (score != 0) {
            score = SCORE_FULL_HOUSE + score;
          } else {
            score = hasFlush(firstCard, secondCard);
            if (score != 0) {
              score = SCORE_FLUSH + score;
            } else {
              score = hasStraight(firstCard, secondCard);
              if (score != 0) {
                score = SCORE_STRAIGHT + score;
              } else {
                score = hasThreeOfAKind(firstCard, secondCard);
                if (score != 0) {
                  score = SCORE_THREE_OF_A_KIND + score;
                } else {
                  score = hasTwoPair(firstCard, secondCard);
                  if (score != 0) {
                    score = SCORE_TWO_PAIRS + score;
                  } else {
                    score = hasPair(firstCard, secondCard);
                    if (score != 0) {
                      score = SCORE_PAIR + score;
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    // That if-else was nasty, but has the optimisation that each check function,
    // e.g. hasPair, does not have to be called twice. We'd like to have
    // } else if (uint x = hasPair(...) != 0) {
    // but it is not possible.

    // Add on the high card value to their score, in case two scores are equal
    // and the winner is determined by the high card.
    score = score + highCardScore(firstCard, secondCard);

    return score;
  }

  function hasRoyalFlush(uint first, uint second) private view returns (bool) {
    return
    // first suit
    tableOrHandContains(8, first, second)  && tableOrHandContains(9, first, second)  &&
    tableOrHandContains(10, first, second) && tableOrHandContains(11, first, second) &&
    tableOrHandContains(12, first, second) ||
    // second suit
    tableOrHandContains(21, first, second) && tableOrHandContains(22, first, second) &&
    tableOrHandContains(23, first, second) && tableOrHandContains(24, first, second) &&
    tableOrHandContains(25, first, second) ||
    // third suit
    tableOrHandContains(34, first, second) && tableOrHandContains(35, first, second) &&
    tableOrHandContains(36, first, second) && tableOrHandContains(37, first, second) &&
    tableOrHandContains(38, first, second) ||
    // fourth suit
    tableOrHandContains(47, first, second) && tableOrHandContains(48, first, second) &&
    tableOrHandContains(49, first, second) && tableOrHandContains(50, first, second) &&
    tableOrHandContains(51, first, second);
  }

  function hasStraightFlush(uint first, uint second) private view returns (uint) {
    for (uint j = 0; j < 51; j += 13) {
      // This inner loop could be optimised...
      for (uint i = j; i < j+7; i++) {
        if (tableOrHandContains(i, first, second)   &&
            tableOrHandContains(i+1, first, second) &&
            tableOrHandContains(i+2, first, second) &&
            tableOrHandContains(i+3, first, second) &&
            tableOrHandContains(i+4, first, second))
          return i+4;
      }
    }
    return 0;
  }

  function hasFourOfAKind(uint first, uint second) private view returns (uint) {
    for (uint i = 0; i < 13; i++) {
      if (tableOrHandContains(i, first, second) &&
          tableOrHandContains(i+13, first, second) &&
          tableOrHandContains(i+26, first, second) &&
          tableOrHandContains(i+39, first, second))
        return i+1;
    }
    return 0;
  }

  function hasFullHouse(uint first, uint second) private view returns (uint) {
    uint threeOfAKind = hasThreeOfAKind(first, second);
    uint pair = hasPair(first, second);
    if ((threeOfAKind != 0) && (pair != 0) && (threeOfAKind != pair))
      return threeOfAKind*13 + pair; // logic ensuring QQQ99 beats 999QQ
    return 0;
  }

  function hasFlush(uint first, uint second) private view returns (uint) {
    uint n = 0; // Number of cards within suit

    // For every suit
    for (uint i = 0; i < 52; i += 13) {
      n = 0;
      if (first >= i && first <= i+12)
        n++;
      if (second >= i && second <= i+12)
        n++;

      uint numTableCards = table.length;
      for (uint j = 0; j < numTableCards; j++) {
        if (table[j] >= i && table[j] <= i+12) {
          n++;
          if (n == 5)
            break;
        }
      }

      if (n == 5)
        break;
    }

    return (n == 5) ? 1 : 0; // High card will determine between two flushes
  }

  function hasStraight(uint first, uint second) private view returns (uint) {
    for (uint i = 0; i < 7; i++) {
      if (tableOrHandContainsMod(i, first, second)   &&
          tableOrHandContainsMod(i+1, first, second) &&
          tableOrHandContainsMod(i+2, first, second) &&
          tableOrHandContainsMod(i+3, first, second) &&
          tableOrHandContainsMod(i+4, first, second))
        return i+4;
    }
    return 0;
  }

  function hasThreeOfAKind(uint first, uint second) private view returns (uint) {
    for (uint i = 0; i < 13; i++) {
      bool _first = tableOrHandContains(i, first, second);
      bool _second = tableOrHandContains(i+13, first, second);
      bool _third = tableOrHandContains(i+26, first, second);
      bool _fourth = tableOrHandContains(i+39, first, second);
      if (_first  && _second && _third  ||
          _first  && _second && _fourth ||
          _second && _third && _fourth)
        return i+1;
    }
    return 0;
  }

  function hasTwoPair(uint first, uint second) private view returns (uint) {
    uint firstPair = hasPair(first, second);
    if (firstPair-1 == 0)
      return 0;

    uint secondPair = 0;
    for (uint i = 0; i < 13; i++) {
      if (i == firstPair-1)
        continue;

      bool _first = tableOrHandContains(i, first, second);
      bool _second = tableOrHandContains(i+13, first, second);
      bool _third = tableOrHandContains(i+26, first, second);
      bool _fourth = tableOrHandContains(i+39, first, second);
      if (_first && _second || _first && _third || _first && _fourth ||
          _second && _third || _second && _fourth || _third && _fourth)
        secondPair = i+1;
    }

    return (secondPair != 0) ? secondPair*13 + firstPair : 0;
  }

  function hasPair(uint first, uint second) private view returns (uint) {
    for (uint i = 0; i < 13; i++) {
      bool _first = tableOrHandContains(i, first, second);
      bool _second = tableOrHandContains(i+13, first, second);
      bool _third = tableOrHandContains(i+26, first, second);
      bool _fourth = tableOrHandContains(i+39, first, second);
      if (_first && _second || _first && _third || _first && _fourth ||
          _second && _third || _second && _fourth || _third && _fourth)
        return i+1;
    }
    return 0;
  }

  function highCardScore(uint first, uint second) private pure returns (uint) {
    return (first > second) ? first : second;
  }

  function tableOrHandContains(uint n, uint first, uint second)
  private view returns (bool) {
    return tableContains(n) || handContains(n, first, second);
  }

  function tableContains(uint n) private view returns (bool) {
    for (uint i = 0; i < table.length; i++) {
      if (table[i] == n)
        return true;
    }
    return false;
  }

  function handContains(uint n, uint first, uint second)
  private pure returns (bool) {
    return n == first || n == second;
  }

  function tableOrHandContainsMod(uint n, uint first, uint second)
  private view returns (bool) {
    return tableContainsMod(n) || handContains(n, first%13, second%13);
  }

  function tableContainsMod(uint n) private view returns (bool) {
    for (uint i = 0; i < table.length; i++) {
      if (table[i]%13 == n)
        return true;
    }
    return false;
  }

}
