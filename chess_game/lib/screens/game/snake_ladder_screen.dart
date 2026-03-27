import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SnakeLadderScreen extends StatefulWidget {
  const SnakeLadderScreen({super.key});

  @override
  State<SnakeLadderScreen> createState() => _SnakeLadderScreenState();
}

class _SnakeLadderScreenState extends State<SnakeLadderScreen>
    with TickerProviderStateMixin {
  static const int boardSize = 10;
  static const int totalSquares = boardSize * boardSize;

  int player1Pos = 1;
  int player2Pos = 1;
  bool isPlayer1Turn = true;
  int lastDiceRoll = 0;
  bool isRolling = false;
  String gameStatus = "Player 1's Turn";
  bool gameOver = false;

  late AnimationController _diceController;
  late Animation<double> _diceAnimation;

  // Snake and Ladder mappings (start: end)
  final Map<int, int> ladders = {
    4: 14,
    9: 31,
    20: 38,
    28: 84,
    40: 59,
    51: 67,
    63: 81,
    71: 91,
  };

  final Map<int, int> snakes = {
    17: 7,
    54: 34,
    62: 19,
    64: 60,
    87: 24,
    93: 73,
    95: 75,
    99: 78,
  };

  @override
  void initState() {
    super.initState();
    _diceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _diceAnimation = CurvedAnimation(
      parent: _diceController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _diceController.dispose();
    super.dispose();
  }

  void _rollDice() async {
    if (isRolling || gameOver) return;

    setState(() {
      isRolling = true;
      gameStatus = "Rolling...";
    });

    await _diceController.forward(from: 0.0);
    
    final random = Random();
    int roll = random.nextInt(6) + 1;

    setState(() {
      lastDiceRoll = roll;
      _movePlayer(roll);
    });
  }

  void _movePlayer(int roll) async {
    int currentPos = isPlayer1Turn ? player1Pos : player2Pos;
    int nextPos = currentPos + roll;

    if (nextPos > totalSquares) {
      // Cannot move beyond 100
      _finishTurn();
      return;
    }

    // Check for ladders or snakes
    if (ladders.containsKey(nextPos)) {
      int bonus = ladders[nextPos]! - nextPos;
      nextPos = ladders[nextPos]!;
      _showSnack("Ladder! +$bonus squares", Colors.green);
    } else if (snakes.containsKey(nextPos)) {
      int penalty = nextPos - snakes[nextPos]!;
      nextPos = snakes[nextPos]!;
      _showSnack("Snake! -$penalty squares", Colors.red);
    }

    setState(() {
      if (isPlayer1Turn) {
        player1Pos = nextPos;
      } else {
        player2Pos = nextPos;
      }
    });

    if (nextPos == totalSquares) {
      setState(() {
        gameOver = true;
        gameStatus = "Player ${isPlayer1Turn ? 1 : 2} Wins!";
      });
      _showVictoryDialog();
    } else {
      _finishTurn();
    }
  }

  void _finishTurn() {
    setState(() {
      isRolling = false;
      isPlayer1Turn = !isPlayer1Turn;
      gameStatus = "Player ${isPlayer1Turn ? 1 : 2}'s Turn";
    });
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showVictoryDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("🎉 Victory!"),
        content: Text("Player ${isPlayer1Turn ? 1 : 2} has reached the finish line!"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetGame();
            },
            child: const Text("Play Again"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/chess');
            },
            child: const Text("Back to Home"),
          ),
        ],
      ),
    );
  }

  void _resetGame() {
    setState(() {
      player1Pos = 1;
      player2Pos = 1;
      isPlayer1Turn = true;
      lastDiceRoll = 0;
      isRolling = false;
      gameStatus = "Player 1's Turn";
      gameOver = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text("Snake & Ladders"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/chess'),
        ),
      ),
      body: Column(
        children: [
          // Game Board
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: boardSize,
                    ),
                    itemCount: totalSquares,
                    itemBuilder: (context, index) {
                      // Board numbers: zig-zag pattern
                      int row = index ~/ boardSize;
                      int col = index % boardSize;
                      
                      int displayNumber;
                      if (row % 2 == 0) {
                        displayNumber = totalSquares - index;
                      } else {
                        int startOfRow = (boardSize - 1 - row) * boardSize + 1;
                        displayNumber = startOfRow + col;
                      }

                      return _buildSquare(displayNumber);
                    },
                  ),
                ),
              ),
            ),
          ),

          // Game Controls
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              children: [
                Text(
                  gameStatus,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isPlayer1Turn ? Colors.blue : Colors.red,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildPlayerStatus(1, player1Pos, Colors.blue, isPlayer1Turn),
                    _buildDice(),
                    _buildPlayerStatus(2, player2Pos, Colors.red, !isPlayer1Turn),
                  ],
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: (isRolling || gameOver) ? null : _rollDice,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isPlayer1Turn ? Colors.blue : Colors.red,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                    ),
                    child: Text(
                      isRolling ? "ROLLING..." : "ROLL DICE",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSquare(int number) {
    bool hasPlayer1 = player1Pos == number;
    bool hasPlayer2 = player2Pos == number;
    bool isLadderStart = ladders.containsKey(number);
    bool isSnakeStart = snakes.containsKey(number);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white10, width: 0.5),
        color: number % 2 == 0 ? Colors.white.withOpacity(0.05) : Colors.transparent,
      ),
      child: Stack(
        children: [
          Center(
            child: Text(
              "$number",
              style: const TextStyle(color: Colors.white24, fontSize: 10),
            ),
          ),
          if (isLadderStart)
            const Positioned(
              top: 2,
              right: 2,
              child: Icon(Icons.arrow_upward, color: Colors.green, size: 12),
            ),
          if (isSnakeStart)
            const Positioned(
              top: 2,
              right: 2,
              child: Icon(Icons.arrow_downward, color: Colors.red, size: 12),
            ),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (hasPlayer1)
                  _buildPawn(Colors.blue),
                if (hasPlayer2)
                  _buildPawn(Colors.red),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPawn(Color color) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerStatus(int id, int pos, Color color, bool isActive) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isActive ? color.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? color : Colors.white12,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Text(
                "P$id",
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              Text(
                "$pos",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDice() {
    return ScaleTransition(
      scale: _diceAnimation,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withOpacity(0.3),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: lastDiceRoll == 0
              ? const Icon(Icons.casino, size: 40, color: Colors.grey)
              : Text(
                  "$lastDiceRoll",
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
        ),
      ),
    );
  }
}
