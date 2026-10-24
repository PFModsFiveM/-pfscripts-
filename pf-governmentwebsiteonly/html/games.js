// ============================================================================
// GAMES MANAGER - Tetris, Minesweeper, Snake, Pong, Memory, Pac-Man, Flappy
// ============================================================================
class GamesManager {
    constructor() {
        this.currentGame = 'tetris';
        this.init();
    }

    init() {
        // Game selector buttons
        document.querySelectorAll('.game-select-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                const game = btn.dataset.game;
                this.switchGame(game);
            });
        });
        // Games initialize lazily when first accessed
    }

    switchGame(game) {
        this.currentGame = game;
        
        // Update buttons
        document.querySelectorAll('.game-select-btn').forEach(btn => {
            btn.classList.toggle('active', btn.dataset.game === game);
        });

        // Update game containers
        document.querySelectorAll('.game-container').forEach(container => {
            container.classList.toggle('active', container.id === `${game}-game`);
        });
        
        // Lazy initialize games when first accessed - use setTimeout to let DOM render
        setTimeout(() => {
            try {
                if (game === 'tetris' && !this.tetris) {
                    this.tetris = new TetrisGame();
                } else if (game === 'minesweeper' && !this.minesweeper) {
                    this.minesweeper = new MinesweeperGame();
                } else if (game === 'snake' && !this.snake) {
                    this.snake = new SnakeGame();
                } else if (game === 'pong' && !this.pong) {
                    this.pong = new PongGame();
                } else if (game === 'memory' && !this.memory) {
                    this.memory = new MemoryGame();
                } else if (game === 'pacman' && !this.pacman) {
                    this.pacman = new PacManGame();
                } else if (game === 'flappy' && !this.flappy) {
                    this.flappy = new FlappyBirdGame();
                }
            } catch (e) {
                console.error('Error initializing game:', game, e);
            }
        }, 100);
    }
}

// ============================================================================
// TETRIS GAME
// ============================================================================
class TetrisGame {
    constructor() {
        this.canvas = document.getElementById('tetris-canvas');
        this.ctx = this.canvas.getContext('2d');
        this.scoreElement = document.getElementById('tetris-score');
        
        this.blockSize = 30;
        this.rows = 20;
        this.cols = 10;
        this.board = [];
        this.currentPiece = null;
        this.currentX = 0;
        this.currentY = 0;
        this.currentColor = 0;
        this.score = 0;
        this.gameLoop = null;
        this.isPaused = false;
        this.gameOver = false;

        this.colors = [
            { main: '#00f0f0', shadow: '#00a0a0' }, // Cyan - I piece
            { main: '#f0a000', shadow: '#c08000' }, // Orange - L piece  
            { main: '#a000f0', shadow: '#7000c0' }, // Purple - T piece
            { main: '#f0f000', shadow: '#c0c000' }, // Yellow - O piece
            { main: '#00f000', shadow: '#00c000' }, // Green - S piece
            { main: '#f00000', shadow: '#c00000' }, // Red - Z piece
            { main: '#0000f0', shadow: '#0000c0' }  // Blue - J piece
        ];
        
        this.pieces = [
            [[1,1,1,1]], // I
            [[1,1],[1,1]], // O
            [[0,1,0],[1,1,1]], // T
            [[1,0,0],[1,1,1]], // L
            [[0,0,1],[1,1,1]], // J
            [[0,1,1],[1,1,0]], // S
            [[1,1,0],[0,1,1]]  // Z
        ];

        this.init();
    }

    resizeCanvas() {
        const wrapper = this.canvas.parentElement;
        if (!wrapper) return;
        
        let maxWidth = wrapper.clientWidth;
        let maxHeight = wrapper.clientHeight;
        
        // Fallback to minimum size if wrapper not sized yet
        if (maxWidth === 0) maxWidth = 300;
        if (maxHeight === 0) maxHeight = 600;
        
        // Maintain aspect ratio (10:20 for Tetris)
        const aspectRatio = this.cols / this.rows;
        let canvasWidth = maxWidth;
        let canvasHeight = canvasWidth / aspectRatio;
        
        if (canvasHeight > maxHeight) {
            canvasHeight = maxHeight;
            canvasWidth = canvasHeight * aspectRatio;
        }
        
        this.canvas.width = this.cols * this.blockSize;
        this.canvas.height = this.rows * this.blockSize;
        this.canvas.style.width = canvasWidth + 'px';
        this.canvas.style.height = canvasHeight + 'px';
        
        if (this.currentPiece) {
            this.draw();
        }
    }

    init() {
        // Make canvas responsive
        this.resizeCanvas();
        window.addEventListener('resize', () => this.resizeCanvas());
        
        document.getElementById('tetris-start').addEventListener('click', () => this.start());
        document.getElementById('tetris-pause').addEventListener('click', () => this.togglePause());
        
        document.addEventListener('keydown', (e) => {
            if (this.gameOver || !this.currentPiece) return;
            
            switch(e.key) {
                case 'ArrowLeft':
                    e.preventDefault();
                    this.move(-1);
                    break;
                case 'ArrowRight':
                    e.preventDefault();
                    this.move(1);
                    break;
                case 'ArrowDown':
                    e.preventDefault();
                    this.moveDown();
                    break;
                case 'ArrowUp':
                    e.preventDefault();
                    this.rotate();
                    break;
                case ' ':
                    e.preventDefault();
                    this.drop();
                    break;
            }
        });

        this.resetBoard();
    }

    start() {
        this.resetBoard();
        this.score = 0;
        this.gameOver = false;
        this.isPaused = false;
        this.scoreElement.textContent = this.score;
        this.spawnPiece();
        
        if (this.gameLoop) clearInterval(this.gameLoop);
        this.gameLoop = setInterval(() => {
            if (!this.isPaused) {
                this.update();
            }
        }, 500);
    }

    togglePause() {
        if (!this.currentPiece) return;
        this.isPaused = !this.isPaused;
    }

    resetBoard() {
        this.board = Array(this.rows).fill().map(() => Array(this.cols).fill(0));
    }

    spawnPiece() {
        const pieceIndex = Math.floor(Math.random() * this.pieces.length);
        this.currentPiece = this.pieces[pieceIndex].map(row => [...row]);
        this.currentColor = pieceIndex;
        this.currentX = Math.floor(this.cols / 2) - Math.floor(this.currentPiece[0].length / 2);
        this.currentY = 0;

        if (this.checkCollision()) {
            this.gameOver = true;
            clearInterval(this.gameLoop);
            
            // Show game over on canvas
            setTimeout(() => {
                this.ctx.fillStyle = 'rgba(0, 0, 0, 0.8)';
                this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
                
                this.ctx.fillStyle = '#ef4444';
                this.ctx.font = 'bold 40px Arial';
                this.ctx.textAlign = 'center';
                this.ctx.fillText('GAME OVER', this.canvas.width / 2, this.canvas.height / 2 - 20);
                
                this.ctx.fillStyle = '#ffffff';
                this.ctx.font = '24px Arial';
                this.ctx.fillText('Score: ' + this.score, this.canvas.width / 2, this.canvas.height / 2 + 30);
                
                this.ctx.font = '18px Arial';
                this.ctx.fillStyle = '#a78bfa';
                this.ctx.fillText('Click "Start" to play again', this.canvas.width / 2, this.canvas.height / 2 + 70);
            }, 100);
        }
    }

    move(dir) {
        this.currentX += dir;
        if (this.checkCollision()) {
            this.currentX -= dir;
        }
        this.draw();
    }

    moveDown() {
        this.currentY++;
        if (this.checkCollision()) {
            this.currentY--;
            this.mergePiece();
            this.clearLines();
            this.spawnPiece();
        }
        this.draw();
    }

    drop() {
        while (!this.checkCollision()) {
            this.currentY++;
        }
        this.currentY--;
        this.mergePiece();
        this.clearLines();
        this.spawnPiece();
        this.draw();
    }

    rotate() {
        const rotated = this.currentPiece[0].map((_, i) =>
            this.currentPiece.map(row => row[i]).reverse()
        );
        const prev = this.currentPiece;
        const prevX = this.currentX;
        this.currentPiece = rotated;
        
        // Try wall kicks if rotation collides
        if (this.checkCollision()) {
            // Try moving left
            this.currentX--;
            if (this.checkCollision()) {
                // Try moving right instead
                this.currentX = prevX + 1;
                if (this.checkCollision()) {
                    // Revert rotation
                    this.currentPiece = prev;
                    this.currentX = prevX;
                }
            }
        }
        this.draw();
    }

    checkCollision() {
        for (let y = 0; y < this.currentPiece.length; y++) {
            for (let x = 0; x < this.currentPiece[y].length; x++) {
                if (this.currentPiece[y][x]) {
                    const newX = this.currentX + x;
                    const newY = this.currentY + y;
                    
                    if (newX < 0 || newX >= this.cols || newY >= this.rows) {
                        return true;
                    }
                    if (newY >= 0 && this.board[newY][newX]) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    mergePiece() {
        for (let y = 0; y < this.currentPiece.length; y++) {
            for (let x = 0; x < this.currentPiece[y].length; x++) {
                if (this.currentPiece[y][x]) {
                    const newY = this.currentY + y;
                    if (newY >= 0) {
                        this.board[newY][this.currentX + x] = this.currentColor + 1;
                    }
                }
            }
        }
    }

    clearLines() {
        let linesCleared = 0;
        for (let y = this.rows - 1; y >= 0; y--) {
            if (this.board[y].every(cell => cell !== 0)) {
                this.board.splice(y, 1);
                this.board.unshift(Array(this.cols).fill(0));
                linesCleared++;
                y++; // Check same row again
            }
        }
        
        if (linesCleared > 0) {
            this.score += linesCleared * 100;
            this.scoreElement.textContent = this.score;
        }
    }

    update() {
        this.moveDown();
    }

    draw() {
        // Only draw if canvas is valid
        if (!this.canvas || this.canvas.width === 0 || this.canvas.height === 0) return;
        
        // Clear canvas
        this.ctx.fillStyle = '#1f2937';
        this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);

        // Draw board with colors
        for (let y = 0; y < this.rows; y++) {
            for (let x = 0; x < this.cols; x++) {
                if (this.board[y][x]) {
                    const colorIndex = this.board[y][x] - 1;
                    const color = this.colors[colorIndex];
                    
                    // Main block
                    this.ctx.fillStyle = color.main;
                    this.ctx.fillRect(x * this.blockSize + 1, y * this.blockSize + 1, this.blockSize - 2, this.blockSize - 2);
                    
                    // Highlight
                    this.ctx.fillStyle = 'rgba(255, 255, 255, 0.3)';
                    this.ctx.fillRect(x * this.blockSize + 2, y * this.blockSize + 2, this.blockSize - 6, 4);
                    
                    // Shadow
                    this.ctx.fillStyle = color.shadow;
                    this.ctx.fillRect(x * this.blockSize + 1, y * this.blockSize + this.blockSize - 6, this.blockSize - 2, 4);
                }
            }
        }

        // Draw current piece with colors
        if (this.currentPiece) {
            const color = this.colors[this.currentColor];
            for (let y = 0; y < this.currentPiece.length; y++) {
                for (let x = 0; x < this.currentPiece[y].length; x++) {
                    if (this.currentPiece[y][x]) {
                        const drawX = (this.currentX + x) * this.blockSize;
                        const drawY = (this.currentY + y) * this.blockSize;
                        
                        // Main block
                        this.ctx.fillStyle = color.main;
                        this.ctx.fillRect(drawX + 1, drawY + 1, this.blockSize - 2, this.blockSize - 2);
                        
                        // Highlight
                        this.ctx.fillStyle = 'rgba(255, 255, 255, 0.4)';
                        this.ctx.fillRect(drawX + 2, drawY + 2, this.blockSize - 6, 4);
                        
                        // Shadow
                        this.ctx.fillStyle = color.shadow;
                        this.ctx.fillRect(drawX + 1, drawY + this.blockSize - 6, this.blockSize - 2, 4);
                    }
                }
            }
        }

        // Draw grid
        this.ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
        this.ctx.lineWidth = 1;
        for (let x = 0; x <= this.cols; x++) {
            this.ctx.beginPath();
            this.ctx.moveTo(x * this.blockSize, 0);
            this.ctx.lineTo(x * this.blockSize, this.canvas.height);
            this.ctx.stroke();
        }
        for (let y = 0; y <= this.rows; y++) {
            this.ctx.beginPath();
            this.ctx.moveTo(0, y * this.blockSize);
            this.ctx.lineTo(this.canvas.width, y * this.blockSize);
            this.ctx.stroke();
        }
    }
}

// ============================================================================
// MINESWEEPER GAME
// ============================================================================
class MinesweeperGame {
    constructor() {
        this.board = [];
        this.revealed = [];
        this.flagged = [];
        this.gameActive = false;
        this.settings = {
            easy: { rows: 8, cols: 8, mines: 10 },
            medium: { rows: 12, cols: 12, mines: 20 },
            hard: { rows: 16, cols: 16, mines: 40 }
        };
        this.currentDifficulty = 'easy';
        this.minesCount = 0;
        this.flagsCount = 0;

        this.init();
    }

    init() {
        document.getElementById('minesweeper-start').addEventListener('click', () => this.start());
        document.getElementById('minesweeper-difficulty').addEventListener('change', (e) => {
            this.currentDifficulty = e.target.value;
        });
    }

    start() {
        const config = this.settings[this.currentDifficulty];
        this.rows = config.rows;
        this.cols = config.cols;
        this.minesCount = config.mines;
        this.flagsCount = 0;
        this.gameActive = true;

        document.getElementById('minesweeper-mines').textContent = this.minesCount;
        document.getElementById('minesweeper-flags').textContent = this.flagsCount;

        this.initBoard();
        this.placeMines();
        this.calculateNumbers();
        this.render();
    }

    initBoard() {
        this.board = Array(this.rows).fill().map(() => Array(this.cols).fill(0));
        this.revealed = Array(this.rows).fill().map(() => Array(this.cols).fill(false));
        this.flagged = Array(this.rows).fill().map(() => Array(this.cols).fill(false));
    }

    placeMines() {
        let minesPlaced = 0;
        while (minesPlaced < this.minesCount) {
            const row = Math.floor(Math.random() * this.rows);
            const col = Math.floor(Math.random() * this.cols);
            
            if (this.board[row][col] !== -1) {
                this.board[row][col] = -1;
                minesPlaced++;
            }
        }
    }

    calculateNumbers() {
        for (let row = 0; row < this.rows; row++) {
            for (let col = 0; col < this.cols; col++) {
                if (this.board[row][col] === -1) continue;
                
                let count = 0;
                for (let dy = -1; dy <= 1; dy++) {
                    for (let dx = -1; dx <= 1; dx++) {
                        const newRow = row + dy;
                        const newCol = col + dx;
                        
                        if (newRow >= 0 && newRow < this.rows && newCol >= 0 && newCol < this.cols) {
                            if (this.board[newRow][newCol] === -1) count++;
                        }
                    }
                }
                this.board[row][col] = count;
            }
        }
    }

    reveal(row, col) {
        if (!this.gameActive || this.revealed[row][col] || this.flagged[row][col]) return;

        this.revealed[row][col] = true;

        if (this.board[row][col] === -1) {
            this.gameOver(false);
            return;
        }

        if (this.board[row][col] === 0) {
            for (let dy = -1; dy <= 1; dy++) {
                for (let dx = -1; dx <= 1; dx++) {
                    const newRow = row + dy;
                    const newCol = col + dx;
                    
                    if (newRow >= 0 && newRow < this.rows && newCol >= 0 && newCol < this.cols) {
                        if (!this.revealed[newRow][newCol]) {
                            this.reveal(newRow, newCol);
                        }
                    }
                }
            }
        }

        this.checkWin();
        this.render();
    }

    toggleFlag(row, col) {
        if (!this.gameActive || this.revealed[row][col]) return;

        this.flagged[row][col] = !this.flagged[row][col];
        this.flagsCount += this.flagged[row][col] ? 1 : -1;
        document.getElementById('minesweeper-flags').textContent = this.flagsCount;
        this.render();
    }

    checkWin() {
        let allRevealed = true;
        for (let row = 0; row < this.rows; row++) {
            for (let col = 0; col < this.cols; col++) {
                if (this.board[row][col] !== -1 && !this.revealed[row][col]) {
                    allRevealed = false;
                    break;
                }
            }
        }

        if (allRevealed) {
            this.gameOver(true);
        }
    }

    gameOver(won) {
        this.gameActive = false;
        
        // Reveal all mines
        for (let row = 0; row < this.rows; row++) {
            for (let col = 0; col < this.cols; col++) {
                if (this.board[row][col] === -1) {
                    this.revealed[row][col] = true;
                }
            }
        }
        
        this.render();
        setTimeout(() => {
            alert(won ? 'You Won!' : 'Game Over!');
        }, 100);
    }

    render() {
        const boardElement = document.getElementById('minesweeper-board');
        boardElement.innerHTML = '';
        boardElement.style.gridTemplateColumns = `repeat(${this.cols}, 30px)`;

        for (let row = 0; row < this.rows; row++) {
            for (let col = 0; col < this.cols; col++) {
                const cell = document.createElement('div');
                cell.className = 'minesweeper-cell';
                
                if (this.revealed[row][col]) {
                    cell.classList.add('revealed');
                    if (this.board[row][col] === -1) {
                        cell.classList.add('mine');
                    } else if (this.board[row][col] > 0) {
                        cell.textContent = this.board[row][col];
                        cell.style.color = this.getNumberColor(this.board[row][col]);
                    }
                } else if (this.flagged[row][col]) {
                    cell.classList.add('flagged');
                }

                cell.addEventListener('click', () => this.reveal(row, col));
                cell.addEventListener('contextmenu', (e) => {
                    e.preventDefault();
                    this.toggleFlag(row, col);
                });

                boardElement.appendChild(cell);
            }
        }
    }

    getNumberColor(num) {
        const colors = ['', '#0000ff', '#008000', '#ff0000', '#000080', '#800000', '#008080', '#000000', '#808080'];
        return colors[num] || '#000';
    }
}

// ============================================================================
// SNAKE GAME
// ============================================================================
class SnakeGame {
    constructor() {
        this.canvas = document.getElementById('snake-canvas');
        this.ctx = this.canvas.getContext('2d');
        this.scoreElement = document.getElementById('snake-score');
        
        this.gridSize = 20;
        this.tileCount = 20;
        this.snake = [];
        this.food = { x: 10, y: 10 };
        this.dx = 0;
        this.dy = 0;
        this.score = 0;
        this.gameLoop = null;
        this.isPaused = false;
        this.gameOver = false;

        this.init();
    }

    resizeCanvas() {
        const wrapper = this.canvas.parentElement;
        if (!wrapper) return;
        
        let maxWidth = wrapper.clientWidth;
        let maxHeight = wrapper.clientHeight;
        
        // Fallback to minimum size if wrapper not sized yet
        if (maxWidth === 0) maxWidth = 400;
        if (maxHeight === 0) maxHeight = 400;
        
        // Maintain square aspect ratio
        const size = Math.min(maxWidth, maxHeight);
        
        this.canvas.width = this.tileCount * this.gridSize;
        this.canvas.height = this.tileCount * this.gridSize;
        this.canvas.style.width = size + 'px';
        this.canvas.style.height = size + 'px';
        
        if (this.snake.length > 0) {
            this.draw();
        }
    }

    init() {
        // Make canvas responsive
        this.resizeCanvas();
        window.addEventListener('resize', () => this.resizeCanvas());
        
        document.getElementById('snake-start').addEventListener('click', () => this.start());
        document.getElementById('snake-pause').addEventListener('click', () => this.togglePause());
        
        document.addEventListener('keydown', (e) => {
            if (this.gameOver) return;
            
            switch(e.key) {
                case 'ArrowLeft':
                case 'a':
                case 'A':
                    if (this.dx === 0) {
                        this.dx = -1;
                        this.dy = 0;
                    }
                    e.preventDefault();
                    break;
                case 'ArrowRight':
                case 'd':
                case 'D':
                    if (this.dx === 0) {
                        this.dx = 1;
                        this.dy = 0;
                    }
                    e.preventDefault();
                    break;
                case 'ArrowUp':
                case 'w':
                case 'W':
                    if (this.dy === 0) {
                        this.dx = 0;
                        this.dy = -1;
                    }
                    e.preventDefault();
                    break;
                case 'ArrowDown':
                case 's':
                case 'S':
                    if (this.dy === 0) {
                        this.dx = 0;
                        this.dy = 1;
                    }
                    e.preventDefault();
                    break;
            }
        });
    }

    start() {
        this.snake = [
            { x: 10, y: 10 },
            { x: 9, y: 10 },
            { x: 8, y: 10 }
        ];
        this.dx = 0; // Start stationary
        this.dy = 0;
        this.score = 0;
        this.gameOver = false;
        this.isPaused = false;
        this.scoreElement.textContent = this.score;
        
        this.placeFood();
        this.draw();
        
        if (this.gameLoop) clearInterval(this.gameLoop);
        this.gameLoop = setInterval(() => {
            if (!this.isPaused && (this.dx !== 0 || this.dy !== 0)) {
                this.update();
                this.draw();
            }
        }, 100);
    }

    togglePause() {
        if (this.snake.length === 0) return;
        this.isPaused = !this.isPaused;
    }

    placeFood() {
        this.food = {
            x: Math.floor(Math.random() * this.tileCount),
            y: Math.floor(Math.random() * this.tileCount)
        };

        // Make sure food doesn't spawn on snake
        const onSnake = this.snake.some(segment => 
            segment.x === this.food.x && segment.y === this.food.y
        );
        
        if (onSnake) {
            this.placeFood();
        }
    }

    update() {
        const head = { x: this.snake[0].x + this.dx, y: this.snake[0].y + this.dy };

        // Check wall collision
        if (head.x < 0 || head.x >= this.tileCount || head.y < 0 || head.y >= this.tileCount) {
            this.endGame();
            return;
        }

        // Check self collision
        const collision = this.snake.some(segment => segment.x === head.x && segment.y === head.y);
        if (collision) {
            this.endGame();
            return;
        }

        this.snake.unshift(head);

        // Check food collision
        if (head.x === this.food.x && head.y === this.food.y) {
            this.score += 10;
            this.scoreElement.textContent = this.score;
            this.placeFood();
        } else {
            this.snake.pop();
        }
    }

    endGame() {
        this.gameOver = true;
        clearInterval(this.gameLoop);
        
        // Show game over message on canvas
        this.ctx.fillStyle = 'rgba(0, 0, 0, 0.8)';
        this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
        
        this.ctx.fillStyle = '#ef4444';
        this.ctx.font = 'bold 40px Arial';
        this.ctx.textAlign = 'center';
        this.ctx.fillText('GAME OVER', this.canvas.width / 2, this.canvas.height / 2 - 20);
        
        this.ctx.fillStyle = '#ffffff';
        this.ctx.font = '24px Arial';
        this.ctx.fillText('Score: ' + this.score, this.canvas.width / 2, this.canvas.height / 2 + 30);
        
        this.ctx.font = '18px Arial';
        this.ctx.fillStyle = '#10b981';
        this.ctx.fillText('Click "Start" to play again', this.canvas.width / 2, this.canvas.height / 2 + 70);
    }

    draw() {
        // Only draw if canvas is valid
        if (!this.canvas || this.canvas.width === 0 || this.canvas.height === 0) return;
        
        // Clear canvas
        this.ctx.fillStyle = '#1f2937';
        this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);

        // Only draw game elements if game has started
        if (this.snake.length === 0) return;
        
        // Draw grid lines
        this.ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
        this.ctx.lineWidth = 1;
        for (let i = 0; i <= this.tileCount; i++) {
            // Vertical lines
            this.ctx.beginPath();
            this.ctx.moveTo(i * this.gridSize, 0);
            this.ctx.lineTo(i * this.gridSize, this.canvas.height);
            this.ctx.stroke();
            
            // Horizontal lines
            this.ctx.beginPath();
            this.ctx.moveTo(0, i * this.gridSize);
            this.ctx.lineTo(this.canvas.width, i * this.gridSize);
            this.ctx.stroke();
        }

        // Draw snake with gradient
        this.snake.forEach((segment, index) => {
            const x = segment.x * this.gridSize;
            const y = segment.y * this.gridSize;
            
            if (index === 0) {
                // Head - brighter with gradient
                const gradient = this.ctx.createLinearGradient(x, y, x + this.gridSize, y + this.gridSize);
                gradient.addColorStop(0, '#10b981');
                gradient.addColorStop(1, '#059669');
                this.ctx.fillStyle = gradient;
                this.ctx.fillRect(x + 1, y + 1, this.gridSize - 2, this.gridSize - 2);
                
                // Eyes
                this.ctx.fillStyle = '#ffffff';
                this.ctx.fillRect(x + 4, y + 4, 3, 3);
                this.ctx.fillRect(x + this.gridSize - 7, y + 4, 3, 3);
            } else {
                // Body - gradient gets darker towards tail
                const alpha = 1 - (index / this.snake.length) * 0.3;
                this.ctx.fillStyle = `rgba(5, 150, 105, ${alpha})`;
                this.ctx.fillRect(x + 1, y + 1, this.gridSize - 2, this.gridSize - 2);
                
                // Highlight
                this.ctx.fillStyle = 'rgba(255, 255, 255, 0.1)';
                this.ctx.fillRect(x + 2, y + 2, this.gridSize - 6, 3);
            }
        });

        // Draw food with glow effect
        const fx = this.food.x * this.gridSize;
        const fy = this.food.y * this.gridSize;
        
        // Only draw if valid coordinates
        if (!Number.isFinite(fx) || !Number.isFinite(fy) || this.gridSize === 0) return;
        
        // Glow
        const glow = this.ctx.createRadialGradient(
            fx + this.gridSize / 2, fy + this.gridSize / 2, 0,
            fx + this.gridSize / 2, fy + this.gridSize / 2, this.gridSize
        );
        glow.addColorStop(0, 'rgba(239, 68, 68, 0.8)');
        glow.addColorStop(1, 'rgba(239, 68, 68, 0)');
        this.ctx.fillStyle = glow;
        this.ctx.fillRect(fx - 2, fy - 2, this.gridSize + 4, this.gridSize + 4);
        
        // Food
        const gradient = this.ctx.createLinearGradient(fx, fy, fx + this.gridSize, fy + this.gridSize);
        gradient.addColorStop(0, '#ef4444');
        gradient.addColorStop(1, '#dc2626');
        this.ctx.fillStyle = gradient;
        this.ctx.beginPath();
        this.ctx.arc(fx + this.gridSize / 2, fy + this.gridSize / 2, this.gridSize / 2 - 2, 0, Math.PI * 2);
        this.ctx.fill();
        
        // Shine
        this.ctx.fillStyle = 'rgba(255, 255, 255, 0.4)';
        this.ctx.beginPath();
        this.ctx.arc(fx + this.gridSize / 2 - 2, fy + this.gridSize / 2 - 2, 3, 0, Math.PI * 2);
        this.ctx.fill();
    }
}

// ============================================================================
// PONG GAME
// ============================================================================
class PongGame {
    constructor() {
        this.canvas = document.getElementById('pong-canvas');
        this.ctx = this.canvas.getContext('2d');
        this.scoreElement = document.getElementById('pong-score');
        this.aiScoreElement = document.getElementById('pong-ai-score');
        
        this.paddleWidth = 12;
        this.paddleHeight = 80;
        this.ballSize = 10;
        
        this.player = { x: 30, y: 160, score: 0 };
        this.ai = { x: 558, y: 160, score: 0 };
        this.ball = { x: 300, y: 200, dx: 4, dy: 3 };
        
        this.gameLoop = null;
        this.isPaused = false;
        this.gameOver = false;
        this.winScore = 5;
        this.keysPressed = {};
        
        this.survivalTime = 0;
        this.survivalTarget = 60; // 60 seconds to win
        
        this.init();
    }
    
    init() {
        this.resizeCanvas();
        window.addEventListener('resize', () => this.resizeCanvas());
        
        document.getElementById('pong-start').addEventListener('click', () => this.start());
        document.getElementById('pong-pause').addEventListener('click', () => this.togglePause());
        
        document.addEventListener('keydown', (e) => {
            const key = e.key.toLowerCase();
            if (['arrowup', 'w', 'arrowdown', 's'].includes(key)) {
                e.preventDefault();
                this.keysPressed[key] = true;
            }
        });
        
        document.addEventListener('keyup', (e) => {
            const key = e.key.toLowerCase();
            if (['arrowup', 'w', 'arrowdown', 's'].includes(key)) {
                e.preventDefault();
                this.keysPressed[key] = false;
            }
        });
        
        this.draw();
    }
    
    resizeCanvas() {
        const wrapper = this.canvas.parentElement;
        if (!wrapper) return;
        
        let maxWidth = wrapper.clientWidth;
        let maxHeight = wrapper.clientHeight;
        
        if (maxWidth === 0) maxWidth = 600;
        if (maxHeight === 0) maxHeight = 400;
        
        const aspectRatio = 600 / 400;
        let canvasWidth = maxWidth;
        let canvasHeight = canvasWidth / aspectRatio;
        
        if (canvasHeight > maxHeight) {
            canvasHeight = maxHeight;
            canvasWidth = canvasHeight * aspectRatio;
        }
        
        this.canvas.width = 600;
        this.canvas.height = 400;
        this.canvas.style.width = canvasWidth + 'px';
        this.canvas.style.height = canvasHeight + 'px';
    }
    
    start() {
        this.player = { x: 30, y: 160, score: 0 };
        this.ai = { x: 558, y: 160, score: 0 };
        this.ball = { x: 300, y: 200, dx: 4, dy: 3 };
        this.gameOver = false;
        this.isPaused = false;
        this.survivalTime = 0;
        this.scoreElement.textContent = 0;
        this.aiScoreElement.textContent = 0;
        
        if (this.gameLoop) clearInterval(this.gameLoop);
        this.gameLoop = setInterval(() => {
            if (!this.isPaused) {
                this.update();
                this.draw();
            }
        }, 1000 / 60);
    }
    
    togglePause() {
        if (!this.gameLoop) return;
        this.isPaused = !this.isPaused;
    }
    
    update() {
        // Move ball
        this.ball.x += this.ball.dx;
        this.ball.y += this.ball.dy;
        
        // Player paddle movement (smooth, continuous)
        const paddleSpeed = 6;
        if (this.keysPressed['arrowup'] || this.keysPressed['w']) {
            this.player.y = Math.max(0, this.player.y - paddleSpeed);
        }
        if (this.keysPressed['arrowdown'] || this.keysPressed['s']) {
            this.player.y = Math.min(this.canvas.height - this.paddleHeight, this.player.y + paddleSpeed);
        }
        
        // Ball collision with top/bottom
        if (this.ball.y <= 0 || this.ball.y >= this.canvas.height - this.ballSize) {
            this.ball.dy *= -1;
        }
        
        // Ball collision with paddles
        if (this.ball.x <= this.player.x + this.paddleWidth &&
            this.ball.y + this.ballSize >= this.player.y &&
            this.ball.y <= this.player.y + this.paddleHeight) {
            this.ball.dx = Math.abs(this.ball.dx);
            this.ball.dy += (Math.random() - 0.5) * 2;
        }
        
        if (this.ball.x + this.ballSize >= this.ai.x &&
            this.ball.y + this.ballSize >= this.ai.y &&
            this.ball.y <= this.ai.y + this.paddleHeight) {
            this.ball.dx = -Math.abs(this.ball.dx);
            this.ball.dy += (Math.random() - 0.5) * 2;
        }
        
        // Instant loss - ball touches left or right border
        if (this.ball.x < 0 || this.ball.x > this.canvas.width) {
            this.endGame(false);
            return;
        }
        
        // Increment survival time (60fps = 60 frames per second)
        this.survivalTime += 1 / 60;
        
        // Check win condition - survive for 60 seconds
        if (this.survivalTime >= this.survivalTarget) {
            this.endGame(true);
            return;
        }
        
        // AI movement
        const aiCenter = this.ai.y + this.paddleHeight / 2;
        const ballCenter = this.ball.y + this.ballSize / 2;
        const aiSpeed = 4;
        
        if (ballCenter < aiCenter - 10) {
            this.ai.y = Math.max(0, this.ai.y - aiSpeed);
        } else if (ballCenter > aiCenter + 10) {
            this.ai.y = Math.min(this.canvas.height - this.paddleHeight, this.ai.y + aiSpeed);
        }
    }
    
    resetBall() {
        this.ball.x = 300;
        this.ball.y = 200;
        this.ball.dx = (Math.random() > 0.5 ? 1 : -1) * 4;
        this.ball.dy = (Math.random() - 0.5) * 4;
    }
    
    endGame(won = false) {
        this.gameOver = true;
        clearInterval(this.gameLoop);
        
        setTimeout(() => {
            this.ctx.fillStyle = 'rgba(0, 0, 0, 0.8)';
            this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
            
            const message = won ? 'YOU WIN!' : 'GAME OVER!';
            const color = won ? '#10b981' : '#ef4444';
            
            this.ctx.fillStyle = color;
            this.ctx.font = 'bold 50px Arial';
            this.ctx.textAlign = 'center';
            this.ctx.fillText(message, this.canvas.width / 2, this.canvas.height / 2 - 20);
            
            this.ctx.fillStyle = '#ffffff';
            this.ctx.font = '20px Arial';
            const timeDisplay = `Survived: ${this.survivalTime.toFixed(1)}s / ${this.survivalTarget}s`;
            this.ctx.fillText(timeDisplay, this.canvas.width / 2, this.canvas.height / 2 + 30);
            
            this.ctx.font = '18px Arial';
            this.ctx.fillStyle = '#60a5fa';
            this.ctx.fillText('Click "Start" to play again', this.canvas.width / 2, this.canvas.height / 2 + 70);
        }, 100);
    }
    
    draw() {
        // Only draw if canvas is valid
        if (!this.canvas || this.canvas.width === 0 || this.canvas.height === 0) return;
        
        // Clear canvas
        this.ctx.fillStyle = '#1f2937';
        this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
        
        // Draw center line
        this.ctx.strokeStyle = 'rgba(255, 255, 255, 0.2)';
        this.ctx.setLineDash([10, 10]);
        this.ctx.beginPath();
        this.ctx.moveTo(this.canvas.width / 2, 0);
        this.ctx.lineTo(this.canvas.width / 2, this.canvas.height);
        this.ctx.stroke();
        this.ctx.setLineDash([]);
        
        // Draw paddles
        const gradient1 = this.ctx.createLinearGradient(this.player.x, 0, this.player.x + this.paddleWidth, 0);
        gradient1.addColorStop(0, '#3b82f6');
        gradient1.addColorStop(1, '#2563eb');
        this.ctx.fillStyle = gradient1;
        this.ctx.fillRect(this.player.x, this.player.y, this.paddleWidth, this.paddleHeight);
        
        const gradient2 = this.ctx.createLinearGradient(this.ai.x, 0, this.ai.x + this.paddleWidth, 0);
        gradient2.addColorStop(0, '#ef4444');
        gradient2.addColorStop(1, '#dc2626');
        this.ctx.fillStyle = gradient2;
        this.ctx.fillRect(this.ai.x, this.ai.y, this.paddleWidth, this.paddleHeight);
        
        // Draw ball
        this.ctx.fillStyle = '#ffffff';
        this.ctx.fillRect(this.ball.x, this.ball.y, this.ballSize, this.ballSize);
        
        // Draw survival timer
        this.ctx.fillStyle = '#fbbf24';
        this.ctx.font = 'bold 32px Arial';
        this.ctx.textAlign = 'center';
        const timeText = this.survivalTime.toFixed(1);
        this.ctx.fillText(`${timeText}s`, this.canvas.width / 2, 40);
        
        // Draw goal indicator
        this.ctx.fillStyle = '#10b981';
        this.ctx.font = '16px Arial';
        this.ctx.fillText(`Goal: ${this.survivalTarget}s`, this.canvas.width / 2, 70);
    }
}

// ============================================================================
// MEMORY MATCH GAME
// ============================================================================
class MemoryGame {
    constructor() {
        this.boardElement = document.getElementById('memory-board');
        this.movesElement = document.getElementById('memory-moves');
        this.pairsElement = document.getElementById('memory-pairs');
        
        this.emojis = ['🎮', '🎯', '🎲', '🎪', '🎨', '🎭', '🎬', '🎤'];
        this.cards = [];
        this.flippedCards = [];
        this.matchedPairs = 0;
        this.moves = 0;
        this.canFlip = true;
        
        this.init();
    }
    
    init() {
        document.getElementById('memory-start').addEventListener('click', () => this.start());
        this.start();
    }
    
    start() {
        this.matchedPairs = 0;
        this.moves = 0;
        this.flippedCards = [];
        this.canFlip = true;
        this.movesElement.textContent = 0;
        this.pairsElement.textContent = '0/8';
        
        // Create card pairs
        this.cards = [...this.emojis, ...this.emojis]
            .sort(() => Math.random() - 0.5)
            .map((emoji, index) => ({ id: index, emoji, matched: false }));
        
        this.renderBoard();
    }
    
    renderBoard() {
        this.boardElement.innerHTML = '';
        
        this.cards.forEach((card, index) => {
            const cardElement = document.createElement('div');
            cardElement.className = 'memory-card';
            cardElement.dataset.index = index;
            
            const inner = document.createElement('div');
            inner.className = 'card-inner';
            inner.textContent = card.emoji;
            
            cardElement.appendChild(inner);
            cardElement.addEventListener('click', () => this.flipCard(index));
            
            if (card.matched) {
                cardElement.classList.add('matched');
            }
            
            this.boardElement.appendChild(cardElement);
        });
    }
    
    flipCard(index) {
        if (!this.canFlip) return;
        if (this.cards[index].matched) return;
        if (this.flippedCards.includes(index)) return;
        if (this.flippedCards.length >= 2) return;
        
        this.flippedCards.push(index);
        const cardElement = this.boardElement.children[index];
        cardElement.classList.add('flipped');
        
        if (this.flippedCards.length === 2) {
            this.moves++;
            this.movesElement.textContent = this.moves;
            this.checkMatch();
        }
    }
    
    checkMatch() {
        this.canFlip = false;
        const [index1, index2] = this.flippedCards;
        const card1 = this.cards[index1];
        const card2 = this.cards[index2];
        
        setTimeout(() => {
            if (card1.emoji === card2.emoji) {
                // Match!
                card1.matched = true;
                card2.matched = true;
                this.matchedPairs++;
                this.pairsElement.textContent = `${this.matchedPairs}/8`;
                
                const cardElement1 = this.boardElement.children[index1];
                const cardElement2 = this.boardElement.children[index2];
                cardElement1.classList.add('matched');
                cardElement2.classList.add('matched');
                
                if (this.matchedPairs === 8) {
                    setTimeout(() => {
                        alert(`You won in ${this.moves} moves! 🎉`);
                    }, 500);
                }
            } else {
                // No match
                const cardElement1 = this.boardElement.children[index1];
                const cardElement2 = this.boardElement.children[index2];
                cardElement1.classList.remove('flipped');
                cardElement2.classList.remove('flipped');
            }
            
            this.flippedCards = [];
            this.canFlip = true;
        }, 800);
    }
}

// ============================================================================
// PAC-MAN GAME
// ============================================================================
class PacManGame {
    constructor() {
        this.canvas = document.getElementById('pacman-canvas');
        this.ctx = this.canvas.getContext('2d');
        this.scoreElement = document.getElementById('pacman-score');
        this.livesElement = document.getElementById('pacman-lives');
        
        this.tileSize = 20;
        this.rows = 31;
        this.cols = 28;
        
        this.pacman = { x: 14, y: 23, dir: 0, nextDir: 0, mouthOpen: 0 };
        this.ghosts = [];
        this.score = 0;
        this.lives = 3;
        this.dots = [];
        this.gameLoop = null;
        this.isPaused = false;
        this.gameOver = false;
        
        // Simple maze (1 = wall, 0 = dot, 2 = power pellet, 3 = empty)
        this.maze = this.createMaze();
        
        this.init();
    }
    
    createMaze() {
        // Classic Pac-Man style maze layout
        const mazeTemplate = [
            "1111111111111111111111111111",
            "1000000000000011000000000001",
            "1000110110101010101011001001",
            "1010010010101010101001001001",
            "1000010000001010000001001001",
            "1011110101011010110101101001",
            "1001010101000000001010100001",
            "1001010101010101010101010101",
            "1000000000010000001000000001",
            "1010101010010101010101010101",
            "1010100000000000000010100001",
            "1010100101010101010010100001",
            "1000000010100010100100000001",
            "1010101010101010101010101001",
            "1010010000000000000010100001",
            "1010010101010101010110100001",
            "1000010000000000000000000001",
            "1011111010111111101101011101",
            "1000000010100000100001010001",
            "1010101010100101010101010101",
            "1000100000100000010000001001",
            "1011100101011101010101011001",
            "1000000001000000000101000001",
            "1010101010101010101010101001",
            "1010010000000010000001010001",
            "1000010101010010101010010001",
            "1011110101010000101010110101",
            "1000000000010101010000000001",
            "1010101010010101010101010101",
            "1000001000000000001000000001",
            "1111111111111111111111111111"
        ];
        
        const maze = [];
        for (let y = 0; y < this.rows; y++) {
            maze[y] = [];
            for (let x = 0; x < this.cols; x++) {
                const cell = mazeTemplate[y][x];
                if (cell === '1') {
                    maze[y][x] = 1; // Wall
                } else {
                    maze[y][x] = 0; // Dot
                }
            }
        }
        
        // Add power pellets in corners
        maze[1][1] = 2;
        maze[1][26] = 2;
        maze[29][1] = 2;
        maze[29][26] = 2;
        
        return maze;
    }
    
    init() {
        this.resizeCanvas();
        window.addEventListener('resize', () => this.resizeCanvas());
        
        document.getElementById('pacman-start').addEventListener('click', () => this.start());
        document.getElementById('pacman-pause').addEventListener('click', () => this.togglePause());
        
        document.addEventListener('keydown', (e) => {
            if (this.gameOver) return;
            
            switch(e.key) {
                case 'ArrowLeft':
                case 'a':
                case 'A':
                    e.preventDefault();
                    this.pacman.nextDir = 2; // Left
                    break;
                case 'ArrowRight':
                case 'd':
                case 'D':
                    e.preventDefault();
                    this.pacman.nextDir = 0; // Right
                    break;
                case 'ArrowUp':
                case 'w':
                case 'W':
                    e.preventDefault();
                    this.pacman.nextDir = 3; // Up
                    break;
                case 'ArrowDown':
                case 's':
                case 'S':
                    e.preventDefault();
                    this.pacman.nextDir = 1; // Down
                    break;
            }
        });
        
        this.draw();
    }
    
    resizeCanvas() {
        const wrapper = this.canvas.parentElement;
        if (!wrapper) return;
        
        let maxWidth = wrapper.clientWidth;
        let maxHeight = wrapper.clientHeight;
        
        if (maxWidth === 0) maxWidth = 560;
        if (maxHeight === 0) maxHeight = 620;
        
        const aspectRatio = 560 / 620;
        let canvasWidth = maxWidth;
        let canvasHeight = canvasWidth / aspectRatio;
        
        if (canvasHeight > maxHeight) {
            canvasHeight = maxHeight;
            canvasWidth = canvasHeight * aspectRatio;
        }
        
        this.canvas.width = 560;
        this.canvas.height = 620;
        this.canvas.style.width = canvasWidth + 'px';
        this.canvas.style.height = canvasHeight + 'px';
    }
    
    start() {
        this.pacman = { x: 14, y: 23, dir: 0, nextDir: 0, mouthOpen: 0 };
        this.score = 0;
        this.lives = 3;
        this.gameOver = false;
        this.isPaused = false;
        this.scoreElement.textContent = 0;
        this.livesElement.textContent = 3;
        
        this.maze = this.createMaze();
        
        // Create ghosts
        this.ghosts = [
            { x: 12, y: 14, dir: 0, color: '#ff0000' },
            { x: 14, y: 14, dir: 1, color: '#ffb8ff' },
            { x: 16, y: 14, dir: 2, color: '#00ffff' },
            { x: 14, y: 16, dir: 3, color: '#ffb852' }
        ];
        
        if (this.gameLoop) clearInterval(this.gameLoop);
        this.gameLoop = setInterval(() => {
            if (!this.isPaused) {
                this.update();
                this.draw();
            }
        }, 150);
    }
    
    togglePause() {
        if (!this.gameLoop) return;
        this.isPaused = !this.isPaused;
    }
    
    update() {
        // Try to change direction
        const dirs = [{ x: 1, y: 0 }, { x: 0, y: 1 }, { x: -1, y: 0 }, { x: 0, y: -1 }];
        const nextDir = dirs[this.pacman.nextDir];
        const newX = this.pacman.x + nextDir.x;
        const newY = this.pacman.y + nextDir.y;
        
        if (this.maze[newY] && this.maze[newY][newX] !== 1) {
            this.pacman.dir = this.pacman.nextDir;
        }
        
        // Move Pac-Man
        const dir = dirs[this.pacman.dir];
        const moveX = this.pacman.x + dir.x;
        const moveY = this.pacman.y + dir.y;
        
        if (this.maze[moveY] && this.maze[moveY][moveX] !== 1) {
            this.pacman.x = moveX;
            this.pacman.y = moveY;
            
            // Eat dot
            if (this.maze[moveY][moveX] === 0) {
                this.maze[moveY][moveX] = 3;
                this.score += 10;
                this.scoreElement.textContent = this.score;
            }
            
            // Eat power pellet
            if (this.maze[moveY][moveX] === 2) {
                this.maze[moveY][moveX] = 3;
                this.score += 50;
                this.scoreElement.textContent = this.score;
            }
        }
        
        // Animate mouth
        this.pacman.mouthOpen = (this.pacman.mouthOpen + 0.3) % 1;
        
        // Move ghosts (simple chase AI)
        this.ghosts.forEach(ghost => {
            const dirs = [{ x: 1, y: 0 }, { x: 0, y: 1 }, { x: -1, y: 0 }, { x: 0, y: -1 }];
            
            // Simple AI: try to move towards Pac-Man
            let bestDir = 0;
            let bestDist = Infinity;
            
            for (let i = 0; i < dirs.length; i++) {
                const nextX = ghost.x + dirs[i].x;
                const nextY = ghost.y + dirs[i].y;
                
                // Check if this is a valid move (not a wall)
                if (this.maze[nextY] && this.maze[nextY][nextX] !== 1) {
                    // Calculate distance to Pac-Man
                    const dist = Math.abs(nextX - this.pacman.x) + Math.abs(nextY - this.pacman.y);
                    if (dist < bestDist) {
                        bestDist = dist;
                        bestDir = i;
                    }
                }
            }
            
            const ghostDir = dirs[bestDir];
            ghost.x += ghostDir.x;
            ghost.y += ghostDir.y;
            ghost.dir = bestDir;
            
            // Check collision with Pac-Man
            if (ghost.x === this.pacman.x && ghost.y === this.pacman.y) {
                this.lives--;
                this.livesElement.textContent = this.lives;
                
                if (this.lives <= 0) {
                    this.endGame();
                } else {
                    // Reset position
                    this.pacman.x = 14;
                    this.pacman.y = 23;
                }
            }
        });
        
        // Check win condition
        let dotsRemaining = 0;
        for (let y = 0; y < this.rows; y++) {
            for (let x = 0; x < this.cols; x++) {
                if (this.maze[y][x] === 0 || this.maze[y][x] === 2) {
                    dotsRemaining++;
                }
            }
        }
        
        if (dotsRemaining === 0) {
            this.endGame(true);
        }
    }
    
    endGame(won = false) {
        this.gameOver = true;
        clearInterval(this.gameLoop);
        
        setTimeout(() => {
            this.ctx.fillStyle = 'rgba(0, 0, 0, 0.8)';
            this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
            
            const message = won ? 'YOU WON!' : 'GAME OVER';
            const color = won ? '#10b981' : '#ef4444';
            
            this.ctx.fillStyle = color;
            this.ctx.font = 'bold 40px Arial';
            this.ctx.textAlign = 'center';
            this.ctx.fillText(message, this.canvas.width / 2, this.canvas.height / 2 - 20);
            
            this.ctx.fillStyle = '#ffffff';
            this.ctx.font = '24px Arial';
            this.ctx.fillText('Score: ' + this.score, this.canvas.width / 2, this.canvas.height / 2 + 30);
            
            this.ctx.font = '18px Arial';
            this.ctx.fillStyle = '#fbbf24';
            this.ctx.fillText('Click "Start" to play again', this.canvas.width / 2, this.canvas.height / 2 + 70);
        }, 100);
    }
    
    draw() {
        // Only draw if canvas is valid
        if (!this.canvas || this.canvas.width === 0 || this.canvas.height === 0) return;
        
        // Clear canvas
        this.ctx.fillStyle = '#000000';
        this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
        
        // Draw maze
        for (let y = 0; y < this.rows; y++) {
            for (let x = 0; x < this.cols; x++) {
                const tile = this.maze[y][x];
                
                if (tile === 1) {
                    // Wall
                    this.ctx.fillStyle = '#2563eb';
                    this.ctx.fillRect(x * this.tileSize, y * this.tileSize, this.tileSize, this.tileSize);
                } else if (tile === 0) {
                    // Dot
                    this.ctx.fillStyle = '#fbbf24';
                    this.ctx.beginPath();
                    this.ctx.arc(
                        x * this.tileSize + this.tileSize / 2,
                        y * this.tileSize + this.tileSize / 2,
                        2, 0, Math.PI * 2
                    );
                    this.ctx.fill();
                } else if (tile === 2) {
                    // Power pellet
                    this.ctx.fillStyle = '#ffffff';
                    this.ctx.beginPath();
                    this.ctx.arc(
                        x * this.tileSize + this.tileSize / 2,
                        y * this.tileSize + this.tileSize / 2,
                        5, 0, Math.PI * 2
                    );
                    this.ctx.fill();
                }
            }
        }
        
        // Draw Pac-Man
        const px = this.pacman.x * this.tileSize + this.tileSize / 2;
        const py = this.pacman.y * this.tileSize + this.tileSize / 2;
        const radius = this.tileSize / 2 - 2;
        const mouthAngle = this.pacman.mouthOpen * 0.4;
        const startAngle = [0, Math.PI / 2, Math.PI, -Math.PI / 2][this.pacman.dir];
        
        this.ctx.fillStyle = '#fbbf24';
        this.ctx.beginPath();
        this.ctx.arc(px, py, radius, startAngle + mouthAngle, startAngle + Math.PI * 2 - mouthAngle);
        this.ctx.lineTo(px, py);
        this.ctx.fill();
        
        // Draw ghosts
        this.ghosts.forEach(ghost => {
            const gx = ghost.x * this.tileSize + this.tileSize / 2;
            const gy = ghost.y * this.tileSize + this.tileSize / 2;
            
            this.ctx.fillStyle = ghost.color;
            this.ctx.beginPath();
            this.ctx.arc(gx, gy, radius, Math.PI, 0);
            this.ctx.lineTo(gx + radius, gy + radius);
            this.ctx.lineTo(gx, gy + radius);
            this.ctx.lineTo(gx - radius, gy + radius);
            this.ctx.closePath();
            this.ctx.fill();
            
            // Eyes
            this.ctx.fillStyle = '#ffffff';
            this.ctx.fillRect(gx - 4, gy - 4, 3, 5);
            this.ctx.fillRect(gx + 1, gy - 4, 3, 5);
        });
    }
}

// ============================================================================
// FLAPPY BIRD GAME
// ============================================================================
class FlappyBirdGame {
    constructor() {
        this.canvas = document.getElementById('flappy-canvas');
        this.ctx = this.canvas.getContext('2d');
        this.scoreElement = document.getElementById('flappy-score');
        this.bestElement = document.getElementById('flappy-best');
        
        this.bird = { x: 100, y: 250, velocity: 0, gravity: 0.5, jump: -9, size: 20 };
        this.pipes = [];
        this.pipeWidth = 60;
        this.pipeGap = 150;
        this.pipeFrequency = 90;
        this.frameCount = 0;
        this.score = 0;
        this.bestScore = 0;
        this.gameLoop = null;
        this.gameOver = false;
        
        this.init();
    }
    
    init() {
        this.resizeCanvas();
        window.addEventListener('resize', () => this.resizeCanvas());
        
        document.getElementById('flappy-start').addEventListener('click', () => this.start());
        
        const jump = () => {
            if (this.gameOver) return;
            if (!this.gameLoop) return;
            this.bird.velocity = this.bird.jump;
        };
        
        document.addEventListener('keydown', (e) => {
            if (e.code === 'Space') {
                e.preventDefault();
                jump();
            }
        });
        
        this.canvas.addEventListener('click', jump);
    }
    
    resizeCanvas() {
        const wrapper = this.canvas.parentElement;
        if (!wrapper) return;
        
        let maxWidth = wrapper.clientWidth;
        let maxHeight = wrapper.clientHeight;
        
        if (maxWidth === 0) maxWidth = 400;
        if (maxHeight === 0) maxHeight = 600;
        
        const aspectRatio = 400 / 600;
        let canvasWidth = maxWidth;
        let canvasHeight = canvasWidth / aspectRatio;
        
        if (canvasHeight > maxHeight) {
            canvasHeight = maxHeight;
            canvasWidth = canvasHeight * aspectRatio;
        }
        
        this.canvas.width = 400;
        this.canvas.height = 600;
        this.canvas.style.width = canvasWidth + 'px';
        this.canvas.style.height = canvasHeight + 'px';
    }
    
    start() {
        this.bird = { x: 100, y: 250, velocity: 0, gravity: 0.5, jump: -9, size: 20 };
        this.pipes = [];
        this.frameCount = 0;
        this.score = 0;
        this.gameOver = false;
        this.scoreElement.textContent = 0;
        
        if (this.gameLoop) clearInterval(this.gameLoop);
        this.gameLoop = setInterval(() => {
            this.update();
            this.draw();
        }, 1000 / 60);
    }
    
    update() {
        // Update bird
        this.bird.velocity += this.bird.gravity;
        this.bird.y += this.bird.velocity;
        
        // Check ground/ceiling collision
        if (this.bird.y + this.bird.size >= this.canvas.height || this.bird.y <= 0) {
            this.endGame();
            return;
        }
        
        // Generate pipes
        this.frameCount++;
        if (this.frameCount % this.pipeFrequency === 0) {
            const minHeight = 50;
            const maxHeight = this.canvas.height - this.pipeGap - minHeight;
            const height = Math.random() * (maxHeight - minHeight) + minHeight;
            
            this.pipes.push({
                x: this.canvas.width,
                top: height,
                bottom: height + this.pipeGap,
                scored: false
            });
        }
        
        // Update pipes
        this.pipes.forEach((pipe, index) => {
            pipe.x -= 3;
            
            // Check collision
            if (this.bird.x + this.bird.size > pipe.x &&
                this.bird.x < pipe.x + this.pipeWidth &&
                (this.bird.y < pipe.top || this.bird.y + this.bird.size > pipe.bottom)) {
                this.endGame();
            }
            
            // Score
            if (!pipe.scored && pipe.x + this.pipeWidth < this.bird.x) {
                pipe.scored = true;
                this.score++;
                this.scoreElement.textContent = this.score;
            }
            
            // Remove off-screen pipes
            if (pipe.x + this.pipeWidth < 0) {
                this.pipes.splice(index, 1);
            }
        });
    }
    
    endGame() {
        this.gameOver = true;
        clearInterval(this.gameLoop);
        
        if (this.score > this.bestScore) {
            this.bestScore = this.score;
            this.bestElement.textContent = this.bestScore;
        }
        
        setTimeout(() => {
            this.ctx.fillStyle = 'rgba(0, 0, 0, 0.8)';
            this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
            
            this.ctx.fillStyle = '#ef4444';
            this.ctx.font = 'bold 40px Arial';
            this.ctx.textAlign = 'center';
            this.ctx.fillText('GAME OVER', this.canvas.width / 2, this.canvas.height / 2 - 40);
            
            this.ctx.fillStyle = '#ffffff';
            this.ctx.font = '24px Arial';
            this.ctx.fillText('Score: ' + this.score, this.canvas.width / 2, this.canvas.height / 2);
            this.ctx.fillText('Best: ' + this.bestScore, this.canvas.width / 2, this.canvas.height / 2 + 35);
            
            this.ctx.font = '18px Arial';
            this.ctx.fillStyle = '#fbbf24';
            this.ctx.fillText('Click "Start" to play again', this.canvas.width / 2, this.canvas.height / 2 + 75);
        }, 100);
    }
    
    draw() {
        // Only draw if canvas is valid
        if (!this.canvas || this.canvas.width === 0 || this.canvas.height === 0) return;
        
        // Sky gradient
        const gradient = this.ctx.createLinearGradient(0, 0, 0, this.canvas.height);
        gradient.addColorStop(0, '#87CEEB');
        gradient.addColorStop(1, '#E0F6FF');
        this.ctx.fillStyle = gradient;
        this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
        
        // Pipes
        this.pipes.forEach(pipe => {
            const pipeGradient = this.ctx.createLinearGradient(pipe.x, 0, pipe.x + this.pipeWidth, 0);
            pipeGradient.addColorStop(0, '#10b981');
            pipeGradient.addColorStop(1, '#059669');
            
            // Top pipe
            this.ctx.fillStyle = pipeGradient;
            this.ctx.fillRect(pipe.x, 0, this.pipeWidth, pipe.top);
            this.ctx.strokeStyle = '#047857';
            this.ctx.lineWidth = 3;
            this.ctx.strokeRect(pipe.x, 0, this.pipeWidth, pipe.top);
            
            // Bottom pipe
            this.ctx.fillRect(pipe.x, pipe.bottom, this.pipeWidth, this.canvas.height - pipe.bottom);
            this.ctx.strokeRect(pipe.x, pipe.bottom, this.pipeWidth, this.canvas.height - pipe.bottom);
        });
        
        // Bird
        const birdGradient = this.ctx.createRadialGradient(
            this.bird.x + this.bird.size / 2, this.bird.y + this.bird.size / 2, 0,
            this.bird.x + this.bird.size / 2, this.bird.y + this.bird.size / 2, this.bird.size
        );
        birdGradient.addColorStop(0, '#fbbf24');
        birdGradient.addColorStop(1, '#f59e0b');
        this.ctx.fillStyle = birdGradient;
        this.ctx.beginPath();
        this.ctx.arc(this.bird.x + this.bird.size / 2, this.bird.y + this.bird.size / 2, this.bird.size / 2, 0, Math.PI * 2);
        this.ctx.fill();
        
        // Bird eye
        this.ctx.fillStyle = '#ffffff';
        this.ctx.beginPath();
        this.ctx.arc(this.bird.x + this.bird.size * 0.7, this.bird.y + this.bird.size * 0.3, 3, 0, Math.PI * 2);
        this.ctx.fill();
        
        this.ctx.fillStyle = '#000000';
        this.ctx.beginPath();
        this.ctx.arc(this.bird.x + this.bird.size * 0.7, this.bird.y + this.bird.size * 0.3, 1.5, 0, Math.PI * 2);
        this.ctx.fill();
        
        // Ground
        this.ctx.fillStyle = '#8B4513';
        this.ctx.fillRect(0, this.canvas.height - 50, this.canvas.width, 50);
    }
}
