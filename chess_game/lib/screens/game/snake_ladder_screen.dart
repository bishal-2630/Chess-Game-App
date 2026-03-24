import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/django_auth_service.dart';

class SnakeLadderScreen extends StatefulWidget {
  const SnakeLadderScreen({super.key});

  @override
  State<SnakeLadderScreen> createState() => _SnakeLadderScreenState();
}

class _SnakeLadderScreenState extends State<SnakeLadderScreen>
    with TickerProviderStateMixin {
  static const int boardSize = 10;
  static const int totalSquares = boardSize * boardSize;

  int player1Pos = 0; // 0 = not started
  int player2Pos = 0;
  bool isPlayer1Turn = true;
  int lastDiceRoll = 0;
  bool isRolling = false;
  String gameStatus = "";
  bool gameOver = false;

  final DjangoAuthService _authService = DjangoAuthService();
  late String p1Name;
  late String p2Name;
  String? p1ImageUrl;
  String? p2ImageUrl;

  late AnimationController _diceController;
  late Animation<double> _diceAnimation;

  // Ladders: bottom square -> top square
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

  // Snakes: head square -> tail square
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
    
    _initializePlayers();
  }

  void _initializePlayers() {
    p1Name = _authService.displayName;
    p2Name = "Player 2";
    p1ImageUrl = _authService.currentUser?['profile_picture'];
    gameStatus = "$p1Name's Turn";
  }

  @override
  void dispose() {
    _diceController.dispose();
    super.dispose();
  }

  /// Converts a board square number (1-100) to a grid (row, col) in the board.
  /// Row 0 = top row, row 9 = bottom row
  /// The board numbering: bottom-left is 1, goes right to 10, then second row
  /// goes left from 20 to 11, etc. (zig-zag)
  Offset _squareToGridPosition(int square) {
    int s = square - 1; // 0-indexed
    int row = s ~/ boardSize;
    int col = s % boardSize;
    // Even rows (0,2,...) go left-to-right, odd rows go right-to-left
    // But visually row 0 is at the bottom, row 9 is at the top
    int visualRow = boardSize - 1 - row;
    int visualCol = (row % 2 == 0) ? col : (boardSize - 1 - col);
    return Offset(visualCol.toDouble(), visualRow.toDouble());
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

  void _movePlayer(int roll) {
    int currentPos = isPlayer1Turn ? player1Pos : player2Pos;
    int nextPos = currentPos + roll;

    if (nextPos > totalSquares) {
      _finishTurn();
      return;
    }

    String? message;
    Color? msgColor;

    if (ladders.containsKey(nextPos)) {
      int bonus = ladders[nextPos]! - nextPos;
      nextPos = ladders[nextPos]!;
      message = "🪜 Ladder! Climb +$bonus squares";
      msgColor = Colors.green;
    } else if (snakes.containsKey(nextPos)) {
      int penalty = nextPos - snakes[nextPos]!;
      nextPos = snakes[nextPos]!;
      message = "🐍 Snake! Slide -$penalty squares";
      msgColor = Colors.red;
    }

    setState(() {
      if (isPlayer1Turn) {
        player1Pos = nextPos;
      } else {
        player2Pos = nextPos;
      }
    });

    if (message != null) {
      _showSnack(message, msgColor!);
    }

    if (nextPos == totalSquares) {
      setState(() {
        gameOver = true;
        gameStatus = "${isPlayer1Turn ? p1Name : p2Name} Wins! 🏆";
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
      gameStatus = "${isPlayer1Turn ? p1Name : p2Name}'s Turn";
    });
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: color,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showVictoryDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("🏆 Victory!"),
        content: Text("${isPlayer1Turn ? p1Name : p2Name} has won the game!"),
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
      player1Pos = 0;
      player2Pos = 0;
      isPlayer1Turn = true;
      lastDiceRoll = 0;
      isRolling = false;
      gameStatus = "$p1Name's Turn";
      gameOver = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: const Text("Snake & Ladders",
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/chess'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetGame,
            tooltip: "Restart",
          ),
        ],
      ),
      body: Column(
        children: [
          // Board
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    double cellSize = constraints.maxWidth / boardSize;
                    return Stack(
                      children: [
                        // Draw the board grid
                        _buildGrid(cellSize),
                        // Draw snakes and ladders via CustomPaint
                        Positioned.fill(
                          child: CustomPaint(
                            painter: SnakeLadderPainter(
                              snakes: snakes,
                              ladders: ladders,
                              boardSize: boardSize,
                              squareToGrid: _squareToGridPosition,
                              cellSize: cellSize,
                            ),
                          ),
                        ),
                        // Draw player tokens on top
                        if (player1Pos > 0) _buildToken(player1Pos, Colors.blue, "P1", cellSize),
                        if (player2Pos > 0) _buildToken(player2Pos, Colors.orange, "P2", cellSize),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),

          // Controls
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  gameStatus,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isPlayer1Turn ? Colors.blue : Colors.orange,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildPlayerCard(p1Name, p1ImageUrl, player1Pos, Colors.blue, isPlayer1Turn),
                    _buildDice(),
                    _buildPlayerCard(p2Name, p2ImageUrl, player2Pos, Colors.orange, !isPlayer1Turn),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: (isRolling || gameOver) ? null : _rollDice,
                    icon: const Icon(Icons.casino),
                    label: Text(
                      isRolling ? "ROLLING..." : "ROLL DICE",
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isPlayer1Turn ? Colors.blue : Colors.orange,
                      disabledBackgroundColor: Colors.grey.shade800,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 8,
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

  Widget _buildGrid(double cellSize) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: boardSize,
      ),
      itemCount: totalSquares,
      itemBuilder: (context, index) {
        int row = index ~/ boardSize;
        int col = index % boardSize;
        int square;
        if (row % 2 == 0) {
          // Even visual rows: left to right but counting from bottom
          // Row 0 (top visual) = squares 91-100
          int boardRow = boardSize - 1 - row;
          square = boardRow * boardSize + col + 1;
        } else {
          int boardRow = boardSize - 1 - row;
          square = boardRow * boardSize + (boardSize - col);
        }

        bool isLadderBottom = ladders.containsKey(square);
        bool isSnakeHead = snakes.containsKey(square);
        bool isLadderTop = ladders.values.contains(square);
        bool isSnakeTail = snakes.values.contains(square);

        Color? cellColor;
        if (isLadderBottom) {
          cellColor = Colors.green.withAlpha(64);
        } else if (isSnakeHead) {
          cellColor = Colors.red.withAlpha(64);
        } else if (isLadderTop) {
          cellColor = Colors.green.withAlpha(38);
        } else if (isSnakeTail) {
          cellColor = Colors.red.withAlpha(38);
        } else {
          cellColor = (row + col) % 2 == 0
              ? Colors.white.withAlpha(18)
              : Colors.transparent;
        }

        return Container(
          decoration: BoxDecoration(
            color: cellColor,
            border: Border.all(color: Colors.white12, width: 0.5),
          ),
          child: Center(
            child: Text(
              "$square",
              style: TextStyle(
                color: (isLadderBottom || isLadderTop)
                    ? Colors.greenAccent.withAlpha(230)
                    : (isSnakeHead || isSnakeTail)
                        ? Colors.redAccent.withAlpha(230)
                        : Colors.white38,
                fontSize: cellSize * 0.22,
                fontWeight: (isLadderBottom || isSnakeHead) ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildToken(int square, Color color, String label, double cellSize) {
    Offset gridPos = _squareToGridPosition(square);
    double left = gridPos.dx * cellSize + cellSize * 0.5 - cellSize * 0.2;
    double top = gridPos.dy * cellSize + cellSize * 0.5 - cellSize * 0.2;

    // Offset P2 slightly so they don't fully overlap
    if (label == "P2") {
      left += cellSize * 0.2;
      top += cellSize * 0.1;
    }

    return Positioned(
      left: left,
      top: top,
      child: Container(
        width: cellSize * 0.4,
        height: cellSize * 0.4,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(128),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
                color: Colors.white,
                fontSize: cellSize * 0.13,
                fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerCard(String name, String? imageUrl, int pos, Color color, bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isActive ? color.withAlpha(38) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? color : Colors.white12,
          width: isActive ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withAlpha(50),
            backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
            child: imageUrl == null
                ? Icon(Icons.person, color: color, size: 20)
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            pos == 0 ? "Start" : "$pos",
            style: const TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _buildDice() {
    return ScaleTransition(
      scale: _diceAnimation,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withAlpha(77),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: lastDiceRoll == 0
              ? const Icon(Icons.casino, size: 36, color: Colors.grey)
              : Text(
                  _diceEmoji(lastDiceRoll),
                  style: const TextStyle(fontSize: 36),
                ),
        ),
      ),
    );
  }

  String _diceEmoji(int n) {
    const emojis = ['⚀', '⚁', '⚂', '⚃', '⚄', '⚅'];
    return emojis[n - 1];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomPainter: draws snake bodies and ladder rungs on the board
// ─────────────────────────────────────────────────────────────────────────────
class SnakeLadderPainter extends CustomPainter {
  final Map<int, int> snakes;
  final Map<int, int> ladders;
  final int boardSize;
  final Offset Function(int) squareToGrid;
  final double cellSize;

  SnakeLadderPainter({
    required this.snakes,
    required this.ladders,
    required this.boardSize,
    required this.squareToGrid,
    required this.cellSize,
  });

  Offset _center(int square) {
    Offset g = squareToGrid(square);
    return Offset(
      g.dx * cellSize + cellSize / 2,
      g.dy * cellSize + cellSize / 2,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawLadders(canvas);
    _drawSnakes(canvas);
  }

  void _drawLadders(Canvas canvas) {
    final railPaint = Paint()
      ..color = Colors.greenAccent.withAlpha(217)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final rungPaint = Paint()
      ..color = Colors.green.shade200.withAlpha(179)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final entry in ladders.entries) {
      Offset bottom = _center(entry.key);
      Offset top = _center(entry.value);

      // Direction perpendicular to the ladder axis
      double dx = top.dx - bottom.dx;
      double dy = top.dy - bottom.dy;
      double len = sqrt(dx * dx + dy * dy);
      double px = -dy / len * (cellSize * 0.2);
      double py = dx / len * (cellSize * 0.2);

      // Two rails
      canvas.drawLine(
        Offset(bottom.dx + px, bottom.dy + py),
        Offset(top.dx + px, top.dy + py),
        railPaint,
      );
      canvas.drawLine(
        Offset(bottom.dx - px, bottom.dy - py),
        Offset(top.dx - px, top.dy - py),
        railPaint,
      );

      // Rungs
      int rungs = max(3, (len / cellSize).round());
      for (int i = 0; i <= rungs; i++) {
        double t = i / rungs;
        double cx = bottom.dx + dx * t;
        double cy = bottom.dy + dy * t;
        canvas.drawLine(
          Offset(cx + px, cy + py),
          Offset(cx - px, cy - py),
          rungPaint,
        );
      }

      // Arrow tip at top
      _drawArrow(canvas, top, Offset(dx, dy)..normalize(), Colors.greenAccent, cellSize * 0.16);
    }
  }

  void _drawSnakes(Canvas canvas) {
    final colors = [
      Colors.red,
      Colors.deepOrange,
      Colors.purple,
      Colors.pink,
      Colors.teal,
    ];

    int i = 0;
    for (final entry in snakes.entries) {
      final Color snakeColor = colors[i % colors.length];
      i++;

      Offset head = _center(entry.key); // high square
      Offset tail = _center(entry.value); // low square

      final bodyPaint = Paint()
        ..color = snakeColor.withAlpha(217)
        ..strokeWidth = cellSize * 0.22
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      // Draw a sinusoidal snake path using a bezier curve
      double midX = (head.dx + tail.dx) / 2 + (tail.dy - head.dy) * 0.35;
      double midY = (head.dy + tail.dy) / 2 + (head.dx - tail.dx) * 0.35;

      final path = Path()
        ..moveTo(head.dx, head.dy)
        ..quadraticBezierTo(midX, midY, tail.dx, tail.dy);

      canvas.drawPath(path, bodyPaint);

      // Scale pattern overlay (lighter outline)
      final scalePaint = Paint()
        ..color = Colors.white.withAlpha(38)
        ..strokeWidth = cellSize * 0.22
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      // Dashed effect via shorter path segments
      final pathMetrics = path.computeMetrics();
      for (final m in pathMetrics) {
        double dist = 0;
        while (dist < m.length) {
          final segment = m.extractPath(dist, dist + cellSize * 0.1);
          canvas.drawPath(segment, scalePaint);
          dist += cellSize * 0.22;
        }
      }

      // Snake head circle
      final headPaint = Paint()
        ..color = snakeColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(head, cellSize * 0.18, headPaint);

      // Eyes
      final eyePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      final pupilPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.fill;

      double dx = tail.dx - head.dx;
      double dy = tail.dy - head.dy;
      double len = sqrt(dx * dx + dy * dy);
      if (len > 0) {
        dx /= len;
        dy /= len;
      }
      double perp = cellSize * 0.07;
      Offset leftEye = Offset(head.dx - dy * perp, head.dy + dx * perp);
      Offset rightEye = Offset(head.dx + dy * perp, head.dy - dx * perp);

      for (final eye in [leftEye, rightEye]) {
        canvas.drawCircle(eye, cellSize * 0.07, eyePaint);
        canvas.drawCircle(eye, cellSize * 0.04, pupilPaint);
      }

      // Tongue
      final tonguePaint = Paint()
        ..color = Colors.red.shade300
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      Offset tongueBase = Offset(head.dx + dx * cellSize * 0.18, head.dy + dy * cellSize * 0.18);
      Offset tongueTip1 = Offset(tongueBase.dx + dx * cellSize * 0.12 - dy * cellSize * 0.06,
          tongueBase.dy + dy * cellSize * 0.12 + dx * cellSize * 0.06);
      Offset tongueTip2 = Offset(tongueBase.dx + dx * cellSize * 0.12 + dy * cellSize * 0.06,
          tongueBase.dy + dy * cellSize * 0.12 - dx * cellSize * 0.06);
      canvas.drawLine(tongueBase, tongueTip1, tonguePaint);
      canvas.drawLine(tongueBase, tongueTip2, tonguePaint);
    }
  }

  void _drawArrow(Canvas canvas, Offset tip, Offset direction, Color color, double size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    double angle = atan2(direction.dy, direction.dx);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - size * cos(angle - 0.5), tip.dy - size * sin(angle - 0.5))
      ..lineTo(tip.dx - size * cos(angle + 0.5), tip.dy - size * sin(angle + 0.5))
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant SnakeLadderPainter old) =>
      old.snakes != snakes || old.ladders != ladders;
}

extension on Offset {
  Offset normalize() {
    double len = distance;
    if (len == 0) return this;
    return this / len;
  }
}
