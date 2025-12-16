// chess_screen.dart - FIXED VERSION
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

class ChessScreen extends StatefulWidget {
  const ChessScreen({Key? key}) : super(key: key);

  @override
  State<ChessScreen> createState() => _ChessGameScreenState();
}

class _ChessGameScreenState extends State<ChessScreen> {
  final User? user = FirebaseAuth.instance.currentUser;

  // Chess board state
  List<List<String>> board = [];
  String selectedPiece = '';
  int selectedRow = -1;
  int selectedCol = -1;
  bool isWhiteTurn = true;
  String status = "White's turn";
  List<List<bool>> validMoves = [];
  List<Map<String, dynamic>> moveHistory = [];

  final Map<String, String> pieceIcons = {
    'wp': '♙',
    'wr': '♖',
    'wn': '♘',
    'wb': '♗',
    'wq': '♕',
    'wk': '♔',
    'bp': '♟',
    'br': '♜',
    'bn': '♞',
    'bb': '♝',
    'bq': '♛',
    'bk': '♚',
  };

  @override
  void initState() {
    super.initState();
    _initializeBoard();
  }

  void _initializeBoard() {
    board = List.generate(8, (_) => List.filled(8, ''));
    validMoves = List.generate(8, (_) => List.filled(8, false));
    moveHistory.clear();

    // Set up initial pieces
    board[0] = ['br', 'bn', 'bb', 'bq', 'bk', 'bb', 'bn', 'br'];
    board[1] = List.filled(8, 'bp');
    board[6] = List.filled(8, 'wp');
    board[7] = ['wr', 'wn', 'wb', 'wq', 'wk', 'wb', 'wn', 'wr'];

    setState(() {
      status = "White's turn";
      isWhiteTurn = true;
      selectedPiece = '';
      selectedRow = -1;
      selectedCol = -1;
    });
  }

  bool _isWhitePiece(String piece) => piece.startsWith('w');
  String _getPieceType(String piece) =>
      piece.length > 1 ? piece.substring(1) : '';

  void _calculateValidMoves(int row, int col, String piece) {
    // Reset all valid moves
    for (int i = 0; i < 8; i++) {
      for (int j = 0; j < 8; j++) {
        validMoves[i][j] = false;
      }
    }

    final pieceType = _getPieceType(piece);
    final isWhite = _isWhitePiece(piece);

    if (pieceType == 'p') {
      // Pawn movement
      final direction = isWhite ? -1 : 1;
      final newRow = row + direction;

      // Forward move
      if (newRow >= 0 && newRow < 8 && board[newRow][col].isEmpty) {
        validMoves[newRow][col] = true;

        // Double move from starting position
        final startRow = isWhite ? 6 : 1;
        if (row == startRow) {
          final doubleRow = row + 2 * direction;
          if (board[doubleRow][col].isEmpty) {
            validMoves[doubleRow][col] = true;
          }
        }
      }

      // Diagonal captures
      for (final dc in [-1, 1]) {
        final newCol = col + dc;
        if (newRow >= 0 && newRow < 8 && newCol >= 0 && newCol < 8) {
          final targetPiece = board[newRow][newCol];
          if (targetPiece.isNotEmpty && _isWhitePiece(targetPiece) != isWhite) {
            validMoves[newRow][newCol] = true;
          }
        }
      }
    } else if (pieceType == 'r') {
      // Rook movement (horizontal and vertical)
      for (int dr in [-1, 0, 1]) {
        for (int dc in [-1, 0, 1]) {
          if ((dr == 0 && dc == 0) || (dr != 0 && dc != 0)) continue;

          for (int step = 1; step < 8; step++) {
            final newRow = row + dr * step;
            final newCol = col + dc * step;

            if (newRow < 0 || newRow >= 8 || newCol < 0 || newCol >= 8) break;

            final targetPiece = board[newRow][newCol];
            if (targetPiece.isEmpty) {
              validMoves[newRow][newCol] = true;
            } else {
              if (_isWhitePiece(targetPiece) != isWhite) {
                validMoves[newRow][newCol] = true;
              }
              break;
            }
          }
        }
      }
    } else if (pieceType == 'n') {
      // Knight movement (L-shape)
      final moves = [
        [-2, -1],
        [-2, 1],
        [-1, -2],
        [-1, 2],
        [1, -2],
        [1, 2],
        [2, -1],
        [2, 1],
      ];

      for (final move in moves) {
        final newRow = row + move[0];
        final newCol = col + move[1];

        if (newRow >= 0 && newRow < 8 && newCol >= 0 && newCol < 8) {
          final targetPiece = board[newRow][newCol];
          if (targetPiece.isEmpty || _isWhitePiece(targetPiece) != isWhite) {
            validMoves[newRow][newCol] = true;
          }
        }
      }
    } else if (pieceType == 'b') {
      // Bishop movement (diagonal)
      for (int dr in [-1, 1]) {
        for (int dc in [-1, 1]) {
          for (int step = 1; step < 8; step++) {
            final newRow = row + dr * step;
            final newCol = col + dc * step;

            if (newRow < 0 || newRow >= 8 || newCol < 0 || newCol >= 8) break;

            final targetPiece = board[newRow][newCol];
            if (targetPiece.isEmpty) {
              validMoves[newRow][newCol] = true;
            } else {
              if (_isWhitePiece(targetPiece) != isWhite) {
                validMoves[newRow][newCol] = true;
              }
              break;
            }
          }
        }
      }
    } else if (pieceType == 'q') {
      // Queen movement (combine rook and bishop)
      // Rook-like moves
      for (int dr in [-1, 0, 1]) {
        for (int dc in [-1, 0, 1]) {
          if (dr == 0 && dc == 0) continue;

          for (int step = 1; step < 8; step++) {
            final newRow = row + dr * step;
            final newCol = col + dc * step;

            if (newRow < 0 || newRow >= 8 || newCol < 0 || newCol >= 8) break;

            final targetPiece = board[newRow][newCol];
            if (targetPiece.isEmpty) {
              validMoves[newRow][newCol] = true;
            } else {
              if (_isWhitePiece(targetPiece) != isWhite) {
                validMoves[newRow][newCol] = true;
              }
              break;
            }
          }
        }
      }
    } else if (pieceType == 'k') {
      // King movement (one square in any direction)
      for (int dr = -1; dr <= 1; dr++) {
        for (int dc = -1; dc <= 1; dc++) {
          if (dr == 0 && dc == 0) continue;

          final newRow = row + dr;
          final newCol = col + dc;

          if (newRow >= 0 && newRow < 8 && newCol >= 0 && newCol < 8) {
            final targetPiece = board[newRow][newCol];
            if (targetPiece.isEmpty || _isWhitePiece(targetPiece) != isWhite) {
              validMoves[newRow][newCol] = true;
            }
          }
        }
      }
    }
  }

  void _onSquareTap(int row, int col) {
    final piece = board[row][col];

    if (selectedPiece.isEmpty) {
      // Selecting a piece
      if (piece.isNotEmpty) {
        final isPieceWhite = _isWhitePiece(piece);
        if ((isPieceWhite && isWhiteTurn) || (!isPieceWhite && !isWhiteTurn)) {
          _calculateValidMoves(row, col, piece);
          setState(() {
            selectedPiece = piece;
            selectedRow = row;
            selectedCol = col;
          });
        }
      }
    } else if (validMoves[row][col]) {
      // Moving to a valid square
      final capturedPiece = board[row][col];

      // Record move
      moveHistory.add({
        'fromRow': selectedRow,
        'fromCol': selectedCol,
        'toRow': row,
        'toCol': col,
        'movedPiece': selectedPiece,
        'capturedPiece': capturedPiece,
        'wasWhiteTurn': isWhiteTurn,
      });

      // Limit history size
      if (moveHistory.length > 50) moveHistory.removeAt(0);

      // Move piece
      setState(() {
        board[row][col] = selectedPiece;
        board[selectedRow][selectedCol] = '';

        // Check for king capture (simplified game over)
        if (_getPieceType(capturedPiece) == 'k') {
          status = '${_isWhitePiece(selectedPiece) ? 'White' : 'Black'} wins!';
          _showGameOverDialog(status);
        } else {
          // Switch turns
          isWhiteTurn = !isWhiteTurn;
          status = isWhiteTurn ? "White's turn" : "Black's turn";
        }

        // Clear selection
        selectedPiece = '';
        selectedRow = -1;
        selectedCol = -1;

        // Clear valid moves
        for (int i = 0; i < 8; i++) {
          for (int j = 0; j < 8; j++) {
            validMoves[i][j] = false;
          }
        }
      });
    } else if (piece.isNotEmpty &&
        _isWhitePiece(piece) == _isWhitePiece(selectedPiece)) {
      // Selecting a different piece of the same color
      _calculateValidMoves(row, col, piece);
      setState(() {
        selectedPiece = piece;
        selectedRow = row;
        selectedCol = col;
      });
    } else {
      // Clicking elsewhere - clear selection
      setState(() {
        selectedPiece = '';
        selectedRow = -1;
        selectedCol = -1;
        for (int i = 0; i < 8; i++) {
          for (int j = 0; j < 8; j++) {
            validMoves[i][j] = false;
          }
        }
      });
    }
  }

  void _undoMove() {
    if (moveHistory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No moves to undo')),
      );
      return;
    }

    final lastMove = moveHistory.removeLast();

    setState(() {
      // Restore captured piece
      board[lastMove['toRow']][lastMove['toCol']] = lastMove['capturedPiece'];
      // Move piece back
      board[lastMove['fromRow']][lastMove['fromCol']] = lastMove['movedPiece'];
      // Restore turn
      isWhiteTurn = lastMove['wasWhiteTurn'];
      status = isWhiteTurn ? "White's turn" : "Black's turn";
      // Clear selection
      selectedPiece = '';
      selectedRow = -1;
      selectedCol = -1;

      // Clear valid moves
      for (int i = 0; i < 8; i++) {
        for (int j = 0; j < 8; j++) {
          validMoves[i][j] = false;
        }
      }
    });
  }

  void _showGameOverDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Game Over'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _initializeBoard();
            },
            child: const Text('New Game'),
          ),
        ],
      ),
    );
  }

  Widget _buildChessSquare(int row, int col) {
    final piece = board[row][col];
    final isWhiteSquare = (row + col) % 2 == 0;
    final isSelected = row == selectedRow && col == selectedCol;
    final isValidMove = validMoves[row][col];

    Color squareColor;
    if (isSelected) {
      squareColor = Colors.yellow.withOpacity(0.5);
    } else if (isValidMove) {
      squareColor = Colors.green.withOpacity(0.3);
    } else {
      squareColor =
          isWhiteSquare ? const Color(0xFFF0D9B5) : const Color(0xFFB58863);
    }

    return GestureDetector(
      onTap: () => _onSquareTap(row, col),
      child: Container(
        decoration: BoxDecoration(
          color: squareColor,
          border: Border.all(color: Colors.black12, width: 0.5),
        ),
        child: Center(
          child: piece.isEmpty
              ? const SizedBox()
              : Text(
                  pieceIcons[piece] ?? '',
                  style: TextStyle(
                    fontSize: 30,
                    color: _isWhitePiece(piece) ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chess Game'),
        backgroundColor: Colors.blue[800],
        actions: [
          // REMOVED LOGOUT BUTTON - logout should be from profile page
          IconButton(
            icon: const Icon(Icons.undo, color: Colors.white),
            onPressed: _undoMove,
            tooltip: 'Undo Move',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _initializeBoard,
            tooltip: 'New Game',
          ),
        ],
      ),
      body: Column(
        children: [
          // User Profile Header - FIXED: Now clickable
          GestureDetector(
            onTap: () => context.go('/profile'),
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.blue[50],
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.blue[100],
                    backgroundImage: user?.photoURL != null
                        ? NetworkImage(user!.photoURL!)
                        : null,
                    child: user?.photoURL == null
                        ? Icon(
                            Icons.person,
                            size: 24,
                            color: Colors.blue[800],
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? 'Chess Player',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          user?.email ?? 'No email',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.grey[500],
                  ),
                ],
              ),
            ),
          ),

          // Game Status
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            color: isWhiteTurn ? Colors.white : Colors.black,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isWhiteTurn ? Colors.black : Colors.white,
                  ),
                ),
                Text(
                  'Moves: ${moveHistory.length}',
                  style: TextStyle(
                    fontSize: 14,
                    color: isWhiteTurn ? Colors.black54 : Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          // Chess Board - FIXED: No blank space
          Expanded(
            child: Center(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.width * 0.9,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.brown, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                  ),
                  itemCount: 64,
                  itemBuilder: (context, index) {
                    final row = index ~/ 8;
                    final col = index % 8;
                    return _buildChessSquare(row, col);
                  },
                ),
              ),
            ),
          ),

          // Controls - FIXED: Removed "Home" button, changed to "Profile"
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _undoMove,
                  icon: const Icon(Icons.undo),
                  label: const Text('Undo Move'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _initializeBoard,
                  icon: const Icon(Icons.refresh),
                  label: const Text('New Game'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => context.go('/profile'),
                  icon: const Icon(Icons.person),
                  label: const Text('Profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
