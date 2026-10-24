class GamesManager {
    constructor() {
        this.playerName = () => (document.querySelector('[data-player-name]')?.textContent || 'Player').trim() || 'Player';
        this.apps = {};
        this.init();
    }

    init() {
        this.apps.minesweeper = new MinesweeperApp('minesweeper-app', this.playerName);
        this.apps.tetris = new TetrisApp('tetris-app', this.playerName);
        this.apps.snake = new SnakeApp('snake-app', this.playerName);
        this.apps.pong = new PongApp('pong-app', this.playerName);
        this.apps.flappy = new FlappyApp('flappy-app', this.playerName);
    }

    switchGame(game) {
        if (this.apps[game] && typeof this.apps[game].focus === 'function') {
            this.apps[game].focus();
        }
    }
}

class LeaderboardStore {
    static key(game) { return `leaderboard_${game}`; }
    static load(game) {
        try { return JSON.parse(localStorage.getItem(this.key(game)) || '[]'); }
        catch { return []; }
    }
    static save(game, list) {
        localStorage.setItem(this.key(game), JSON.stringify(list.slice(0, 10)));
    }
    static submit(game, name, score, meta='') {
        const list = this.load(game);
        list.push({ name, score, meta, ts: Date.now() });
        list.sort((a,b) => b.score - a.score);
        this.save(game, list);
        return list.slice(0, 10);
    }
    static submitLowerIsBetter(game, name, score, meta='') {
        const list = this.load(game);
        list.push({ name, score, meta, ts: Date.now() });
        list.sort((a,b) => a.score - b.score);
        this.save(game, list);
        return list.slice(0, 10);
    }
}

class BaseGameApp {
    constructor(rootId, playerNameGetter, config) {
        this.root = document.getElementById(rootId);
        this.getPlayerName = playerNameGetter;
        this.config = config;
        if (!this.root) return;
        this.renderShell();
        this.bindBase();
        this.renderLeaderboard();
    }

    renderShell() {
        this.root.innerHTML = `
            <div class="game-shell-header">
                <div>
                    <div class="game-shell-title">${this.config.title}</div>
                    <div class="game-shell-sub">${this.config.subtitle}</div>
                </div>
                <div class="game-shell-controls" id="${this.config.key}-controls"></div>
            </div>
            <div class="game-shell-body">
                <div class="game-stage-card" id="${this.config.key}-stage"></div>
                <aside class="game-side-card">
                    <div class="game-score-grid" id="${this.config.key}-stats"></div>
                    <div>
                        <div class="game-shell-sub" style="margin-bottom:10px">Leaderboard</div>
                        <div class="game-leaderboard" id="${this.config.key}-leaderboard"></div>
                    </div>
                </aside>
            </div>`;
        this.controlsEl = this.root.querySelector(`#${this.config.key}-controls`);
        this.stageEl = this.root.querySelector(`#${this.config.key}-stage`);
        this.statsEl = this.root.querySelector(`#${this.config.key}-stats`);
        this.leaderboardEl = this.root.querySelector(`#${this.config.key}-leaderboard`);
    }

    bindBase() {}
    focus() {}
    renderControls() {}

    setStats(items) {
        this.statsEl.innerHTML = items.map(item => `<div class="game-stat"><label>${item.label}</label><strong>${item.value}</strong></div>`).join('');
    }

    renderLeaderboard() {
        const list = LeaderboardStore.load(this.config.key);
        if (!list.length) {
            this.leaderboardEl.innerHTML = '<div class="game-shell-sub">No scores yet.</div>';
            return;
        }
        this.leaderboardEl.innerHTML = list.map((entry, idx) => `
            <div class="game-leaderboard-row">
                <span>#${idx + 1}</span>
                <div><strong>${entry.name}</strong><div class="game-shell-sub">${entry.meta || 'Best run'}</div></div>
                <strong>${entry.score}</strong>
            </div>`).join('');
    }
}

class MinesweeperApp extends BaseGameApp {
    constructor(rootId, playerNameGetter) {
        super(rootId, playerNameGetter, { key: 'minesweeper', title: 'Minesweeper', subtitle: 'Clear the field without hitting a mine.' });
        if (!this.root) return;
        this.difficulties = { easy: [9, 9, 10], medium: [16, 16, 40], hard: [16, 30, 99] };
        this.currentDifficulty = 'easy';
        this.timer = null;
        this.renderControls();
        this.newGame();
    }

    renderControls() {
        this.controlsEl.innerHTML = `
            <select id="minesweeper-difficulty-select">
                <option value="easy">Easy</option>
                <option value="medium">Medium</option>
                <option value="hard">Hard</option>
            </select>
            <button id="minesweeper-new-btn">New game</button>`;
        this.controlsEl.querySelector('#minesweeper-difficulty-select').addEventListener('change', e => {
            this.currentDifficulty = e.target.value;
            this.newGame();
        });
        this.controlsEl.querySelector('#minesweeper-new-btn').addEventListener('click', () => this.newGame());
    }

    newGame() {
        clearInterval(this.timer);
        const [rows, cols, mines] = this.difficulties[this.currentDifficulty];
        this.rows = rows; this.cols = cols; this.mineCount = mines; this.flags = 0; this.seconds = 0; this.started = false; this.revealed = 0; this.finished = false;
        this.board = Array.from({ length: rows }, () => Array.from({ length: cols }, () => ({ mine: false, revealed: false, flagged: false, count: 0 })));
        let placed = 0;
        while (placed < mines) {
            const r = Math.floor(Math.random() * rows), c = Math.floor(Math.random() * cols);
            if (!this.board[r][c].mine) { this.board[r][c].mine = true; placed++; }
        }
        for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
            if (this.board[r][c].mine) continue;
            let count = 0;
            for (let dr = -1; dr <= 1; dr++) for (let dc = -1; dc <= 1; dc++) {
                const nr = r + dr, nc = c + dc;
                if (nr >= 0 && nr < rows && nc >= 0 && nc < cols && this.board[nr][nc].mine) count++;
            }
            this.board[r][c].count = count;
        }
        this.renderBoard();
        this.updateStats();
    }

    updateStats() {
        this.setStats([{ label: 'Mines', value: this.mineCount }, { label: 'Flags', value: this.flags }, { label: 'Time', value: `${this.seconds}s` }, { label: 'Difficulty', value: this.currentDifficulty }]);
    }

    startTimer() {
        if (this.started) return;
        this.started = true;
        this.timer = setInterval(() => { this.seconds++; this.updateStats(); }, 1000);
    }

    renderBoard() {
        this.stageEl.innerHTML = '<div class="minesweeper-board" id="minesweeper-board-grid"></div>';
        const boardEl = this.stageEl.querySelector('#minesweeper-board-grid');
        boardEl.style.gridTemplateColumns = `repeat(${this.cols}, 34px)`;
        for (let r = 0; r < this.rows; r++) for (let c = 0; c < this.cols; c++) {
            const cell = document.createElement('button');
            cell.className = 'mine-cell';
            cell.dataset.r = r; cell.dataset.c = c;
            cell.addEventListener('click', () => this.reveal(r, c));
            cell.addEventListener('contextmenu', e => { e.preventDefault(); this.toggleFlag(r, c); });
            boardEl.appendChild(cell);
        }
        this.refreshBoard();
    }

    refreshBoard() {
        const boardEl = this.stageEl.querySelector('#minesweeper-board-grid');
        if (!boardEl) return;
        boardEl.querySelectorAll('.mine-cell').forEach(cell => {
            const r = Number(cell.dataset.r), c = Number(cell.dataset.c), data = this.board[r][c];
            cell.className = 'mine-cell';
            cell.textContent = '';
            if (data.revealed) {
                cell.classList.add('revealed');
                if (data.mine) { cell.classList.add('mine'); cell.textContent = '✹'; }
                else if (data.count) { cell.textContent = data.count; cell.style.color = ['#fff','#60a5fa','#34d399','#fbbf24','#f87171','#c084fc','#2dd4bf','#f472b6'][data.count]; }
            } else if (data.flagged) {
                cell.classList.add('flagged'); cell.textContent = '⚑';
            }
        });
    }

    toggleFlag(r, c) {
        const cell = this.board[r][c];
        if (cell.revealed || this.finished) return;
        cell.flagged = !cell.flagged;
        this.flags += cell.flagged ? 1 : -1;
        this.updateStats();
        this.refreshBoard();
    }

    reveal(r, c) {
        if (this.finished) return;
        const cell = this.board[r][c];
        if (cell.revealed || cell.flagged) return;
        this.startTimer();
        cell.revealed = true;
        this.revealed++;
        if (cell.mine) {
            this.finished = true;
            clearInterval(this.timer);
            this.board.flat().forEach(entry => { if (entry.mine) entry.revealed = true; });
            this.refreshBoard();
            return;
        }
        if (cell.count === 0) {
            for (let dr = -1; dr <= 1; dr++) for (let dc = -1; dc <= 1; dc++) {
                const nr = r + dr, nc = c + dc;
                if (nr >= 0 && nr < this.rows && nc >= 0 && nc < this.cols) {
                    const next = this.board[nr][nc];
                    if (!next.revealed && !next.mine) this.reveal(nr, nc);
                }
            }
        }
        if (this.revealed >= this.rows * this.cols - this.mineCount) {
            this.finished = true;
            clearInterval(this.timer);
            LeaderboardStore.submitLowerIsBetter('minesweeper', this.getPlayerName(), this.seconds, this.currentDifficulty);
            this.renderLeaderboard();
        }
        this.updateStats();
        this.refreshBoard();
    }
}

class TetrisApp extends BaseGameApp {
    constructor(rootId, playerNameGetter) {
        super(rootId, playerNameGetter, { key: 'tetris', title: 'Tetris', subtitle: 'Stack pieces, clear lines, chase a high score.' });
        if (!this.root) return;
        this.shapes = {
            I:[[1,1,1,1]], O:[[1,1],[1,1]], T:[[0,1,0],[1,1,1]], L:[[0,0,1],[1,1,1]], J:[[1,0,0],[1,1,1]], S:[[0,1,1],[1,1,0]], Z:[[1,1,0],[0,1,1]]
        };
        this.colors = { I:'#32d3ff', O:'#ffe24a', T:'#b84cff', L:'#ff9d2e', J:'#3b82f6', S:'#5cff5c', Z:'#ff5252' };
        this.renderControls();
        this.mount();
        this.reset(false);
    }
    renderControls() {
        this.controlsEl.innerHTML = `<button id="tetris-start-btn">Start</button><button id="tetris-pause-btn">Pause</button>`;
        this.controlsEl.querySelector('#tetris-start-btn').addEventListener('click', () => this.reset(true));
        this.controlsEl.querySelector('#tetris-pause-btn').addEventListener('click', () => this.paused = !this.paused);
    }
    mount() {
        this.stageEl.innerHTML = `<canvas id="tetris-canvas-app" class="game-canvas game-canvas-tetris" width="960" height="720"></canvas>`;
        this.canvas = this.stageEl.querySelector('canvas');
        this.ctx = this.canvas.getContext('2d');
        document.addEventListener('keydown', e => {
            if (document.getElementById('tetris-window')?.style.display === 'none') return;
            if (this.over || this.paused) return;
            if (e.key === 'ArrowLeft') this.tryMove(-1, 0);
            if (e.key === 'ArrowRight') this.tryMove(1, 0);
            if (e.key === 'ArrowDown') this.step();
            if (e.key === 'ArrowUp') this.rotate();
            if (e.key === ' ') { e.preventDefault(); while (this.tryMove(0,1)) {} this.lock(); }
            if (e.key.toLowerCase() === 'c') this.holdPiece();
        });
    }
    nextPiece() { if (!this.bag.length) this.bag = ['I','O','T','L','J','S','Z'].sort(() => Math.random() - .5); return this.bag.pop(); }
    cloneShape(type) { return this.shapes[type].map(r => [...r]); }
    reset(startLoop=true) {
        this.rows = 20; this.cols = 10; this.board = Array.from({length:this.rows},()=>Array(this.cols).fill(''));
        this.score = 0; this.lines = 0; this.level = 1; this.paused = false; this.over = false; this.hold = null; this.canHold = true; this.bag=[]; this.queue=[this.nextPiece(),this.nextPiece(),this.nextPiece()];
        this.spawn(); this.updateStats(); this.draw();
        clearInterval(this.loop); if (startLoop) this.loop = setInterval(() => { if (!this.paused && !this.over) this.step(); }, 650);
    }
    spawn() { const type=this.queue.shift(); this.queue.push(this.nextPiece()); this.activeType=type; this.active=this.cloneShape(type); this.x=3; this.y=0; this.canHold=true; if (this.collides(this.x,this.y,this.active)) this.gameOver(); }
    holdPiece() { if (!this.canHold) return; const current=this.activeType; if (this.hold) { this.activeType=this.hold; this.active=this.cloneShape(this.activeType); this.hold=current; this.x=3; this.y=0; } else { this.hold=current; this.spawn(); } this.canHold=false; this.draw(); }
    collides(x,y,shape){ for(let r=0;r<shape.length;r++) for(let c=0;c<shape[r].length;c++) if(shape[r][c]){ const nx=x+c, ny=y+r; if(nx<0||nx>=this.cols||ny>=this.rows) return true; if(ny>=0&&this.board[ny][nx]) return true; } return false; }
    tryMove(dx,dy){ if(!this.collides(this.x+dx,this.y+dy,this.active)){ this.x+=dx; this.y+=dy; this.draw(); return true; } return false; }
    rotate(){ const rot=this.active[0].map((_,i)=>this.active.map(row=>row[i]).reverse()); if(!this.collides(this.x,this.y,rot)){ this.active=rot; this.draw(); } }
    ghostY(){ let gy=this.y; while(!this.collides(this.x,gy+1,this.active)) gy++; return gy; }
    step(){ if(!this.tryMove(0,1)) this.lock(); }
    lock(){ this.active.forEach((row,r)=>row.forEach((v,c)=>{ if(v&&this.y+r>=0) this.board[this.y+r][this.x+c]=this.activeType; })); let cleared=0; for(let r=this.rows-1;r>=0;r--){ if(this.board[r].every(Boolean)){ this.board.splice(r,1); this.board.unshift(Array(this.cols).fill('')); cleared++; r++; } } if(cleared){ this.lines+=cleared; this.score += [0,100,300,500,800][cleared]*this.level; this.level=1+Math.floor(this.lines/10); clearInterval(this.loop); this.loop=setInterval(()=>{ if(!this.paused&&!this.over) this.step(); }, Math.max(120,700-(this.level-1)*55)); } this.spawn(); this.updateStats(); this.draw(); }
    updateStats(){ this.setStats([{label:'Score',value:this.score},{label:'Level',value:this.level},{label:'Lines',value:this.lines},{label:'Hold',value:this.hold||'-'}]); }
    gameOver(){ this.over=true; clearInterval(this.loop); LeaderboardStore.submit('tetris', this.getPlayerName(), this.score, `Level ${this.level}`); this.renderLeaderboard(); this.draw(); }
    drawBlock(px,py,size,color,ghost=false){ const c=this.ctx; c.save(); c.globalAlpha = ghost ? 0.22 : 1; c.fillStyle = color; c.fillRect(px+1,py+1,size-2,size-2); c.fillStyle='rgba(255,255,255,0.28)'; c.fillRect(px+1,py+1,size-2,Math.max(6,size*0.16)); c.fillStyle='rgba(255,255,255,0.12)'; c.fillRect(px+1,py+1,Math.max(6,size*0.16),size-2); c.fillStyle='rgba(0,0,0,0.28)'; c.fillRect(px+1,py+size-8,size-2,7); c.fillRect(px+size-8,py+1,7,size-2); c.restore(); }
    drawMini(shapeType, x, y, size=18){ const shape=this.cloneShape(shapeType); shape.forEach((row,r)=>row.forEach((v,c)=>{ if(v) this.drawBlock(x+c*size, y+r*size, size, this.colors[shapeType]); })); }
    draw(){
        const c=this.ctx, cw=this.canvas.width, ch=this.canvas.height; c.clearRect(0,0,cw,ch);
        const panelX=76, cell=30, boardW=this.cols*cell, boardH=this.rows*cell, boardX=(cw-boardW)/2-10, boardY=(ch-boardH)/2;
        c.fillStyle='#0f1118'; c.fillRect(0,0,cw,ch);
        c.fillStyle='#05060b'; c.fillRect(boardX-16, boardY-16, boardW+32, boardH+32);
        c.strokeStyle='rgba(255,255,255,0.08)'; c.lineWidth=2; c.strokeRect(boardX-16, boardY-16, boardW+32, boardH+32);
        const grad=c.createLinearGradient(boardX,boardY,boardX,boardY+boardH); grad.addColorStop(0,'#0a1740'); grad.addColorStop(1,'#101215'); c.fillStyle=grad; c.fillRect(boardX,boardY,boardW,boardH);
        for(let r=0;r<this.rows;r++) for(let col=0;col<this.cols;col++){ c.strokeStyle='rgba(130,160,255,0.11)'; c.strokeRect(boardX+col*cell, boardY+r*cell, cell, cell); if(this.board[r][col]) this.drawBlock(boardX+col*cell, boardY+r*cell, cell, this.colors[this.board[r][col]]); }
        const gy=this.ghostY(); this.active.forEach((row,r)=>row.forEach((v,col)=>{ if(v) this.drawBlock(boardX+(this.x+col)*cell, boardY+(gy+r)*cell, cell, this.colors[this.activeType], true); }));
        this.active.forEach((row,r)=>row.forEach((v,col)=>{ if(v) this.drawBlock(boardX+(this.x+col)*cell, boardY+(this.y+r)*cell, cell, this.colors[this.activeType]); }));
        c.fillStyle='rgba(255,255,255,0.07)'; c.fillRect(panelX, boardY+20, 170, 120); c.fillRect(boardX+boardW+36, boardY+20, 170, 180);
        c.fillStyle='#d7def6'; c.font='600 18px Segoe UI'; c.fillText('HOLD', panelX+18, boardY+46); c.fillText('NEXT', boardX+boardW+54, boardY+46);
        if(this.hold) this.drawMini(this.hold, panelX+24, boardY+60, 22); this.queue.slice(0,3).forEach((type,i)=>this.drawMini(type, boardX+boardW+60, boardY+60+i*58, 18));
        c.fillStyle='rgba(255,255,255,0.85)'; c.font='700 18px Segoe UI'; c.fillText(`Score ${this.score}`, panelX, boardY+180); c.fillText(`Level ${this.level}`, panelX, boardY+210); c.fillText(`Lines ${this.lines}`, panelX, boardY+240);
        if(this.over){ c.fillStyle='rgba(0,0,0,.55)'; c.fillRect(boardX,boardY,boardW,boardH); c.fillStyle='#fff'; c.font='700 46px Segoe UI'; c.textAlign='center'; c.fillText('Game Over', boardX+boardW/2, boardY+boardH/2); c.textAlign='left'; }
    }
}

class SnakeApp extends BaseGameApp {
    constructor(rootId, playerNameGetter) {
        super(rootId, playerNameGetter, { key: 'snake', title: 'Snake', subtitle: 'Grow longer, move faster, survive longer.' });
        if (!this.root) return;
        this.renderControls();
        this.mount();
        this.reset(false);
    }
    renderControls(){ this.controlsEl.innerHTML = `<select id="snake-walls"><option value="on">Walls on</option><option value="off">Walls off</option></select><button id="snake-start-btn">Start</button>`; this.controlsEl.querySelector('#snake-start-btn').addEventListener('click', ()=>this.reset(true)); this.controlsEl.querySelector('#snake-walls').addEventListener('change', e => { this.wrap = e.target.value === 'off'; this.updateStats(); }); }
    mount(){ this.stageEl.innerHTML = `<canvas class="game-canvas game-canvas-snake" width="720" height="720"></canvas>`; this.canvas=this.stageEl.querySelector('canvas'); this.ctx=this.canvas.getContext('2d'); document.addEventListener('keydown', e => { if (document.getElementById('snake-window')?.style.display === 'none') return; const k=e.key; if(k==='ArrowUp'&&this.dir.y!==1)this.nextDir={x:0,y:-1}; if(k==='ArrowDown'&&this.dir.y!==-1)this.nextDir={x:0,y:1}; if(k==='ArrowLeft'&&this.dir.x!==1)this.nextDir={x:-1,y:0}; if(k==='ArrowRight'&&this.dir.x!==-1)this.nextDir={x:1,y:0}; }); }
    reset(start=true){ this.grid=18; this.size=Math.floor(this.canvas.width/this.grid); this.snake=[{x:6,y:8},{x:5,y:8},{x:4,y:8}]; this.dir={x:1,y:0}; this.nextDir={x:1,y:0}; this.wrap=this.controlsEl.querySelector('#snake-walls')?.value==='off'; this.score=0; this.over=false; this.placeFood(); this.updateStats(); this.draw(); clearInterval(this.loop); if(start)this.loop=setInterval(()=>this.tick(), 155); }
    placeFood(){ do { this.food={x:Math.floor(Math.random()*this.grid), y:Math.floor(Math.random()*this.grid)}; } while(this.snake.some(s=>s.x===this.food.x&&s.y===this.food.y)); }
    tick(){ if(this.over) return; this.dir=this.nextDir; let head={x:this.snake[0].x+this.dir.x,y:this.snake[0].y+this.dir.y}; if(this.wrap){ head.x=(head.x+this.grid)%this.grid; head.y=(head.y+this.grid)%this.grid; } if(head.x<0||head.y<0||head.x>=this.grid||head.y>=this.grid||this.snake.some(s=>s.x===head.x&&s.y===head.y)){ this.gameOver(); return; } this.snake.unshift(head); if(head.x===this.food.x&&head.y===this.food.y){ this.score++; this.placeFood(); clearInterval(this.loop); this.loop=setInterval(()=>this.tick(), Math.max(70, 155-this.score*4)); } else this.snake.pop(); this.updateStats(); this.draw(); }
    updateStats(){ this.setStats([{label:'Score',value:this.score},{label:'Length',value:this.snake.length},{label:'Speed',value:`${Math.max(1, Math.floor((155-Math.max(70,155-this.score*4))/10))}`},{label:'Walls',value:this.wrap?'Wrap':'Solid'}]); }
    gameOver(){ this.over=true; clearInterval(this.loop); LeaderboardStore.submit('snake', this.getPlayerName(), this.score, `${this.snake.length} length`); this.renderLeaderboard(); this.draw(); }
    drawApple(x,y,size){ const c=this.ctx; c.save(); c.fillStyle='#ea4335'; c.beginPath(); c.arc(x+size*0.45,y+size*0.52,size*0.28,0,Math.PI*2); c.arc(x+size*0.58,y+size*0.48,size*0.24,0,Math.PI*2); c.fill(); c.fillStyle='#7f1d1d'; c.fillRect(x+size*0.52,y+size*0.18,size*0.05,size*0.16); c.fillStyle='#4ade80'; c.beginPath(); c.ellipse(x+size*0.62,y+size*0.18,size*0.12,size*0.07,0.6,0,Math.PI*2); c.fill(); c.restore(); }
    draw(){ const c=this.ctx, cw=this.canvas.width, ch=this.canvas.height, s=this.size; c.clearRect(0,0,cw,ch); c.fillStyle='#5f8f2f'; c.fillRect(0,0,cw,ch); for(let y=0;y<this.grid;y++) for(let x=0;x<this.grid;x++){ c.fillStyle=(x+y)%2===0?'#a7d64f':'#b3da59'; c.fillRect(x*s,y*s,s,s); }
        this.drawApple(this.food.x*s, this.food.y*s, s);
        this.snake.slice().reverse().forEach((seg, idxRev) => { const idx=this.snake.length-1-idxRev; const px=seg.x*s, py=seg.y*s; const radius=s*0.22; c.fillStyle=idx===0?'#3b82f6':'#4f88ff'; c.beginPath(); c.roundRect(px+2,py+2,s-4,s-4,radius); c.fill(); if(idx===0){ c.fillStyle='#fff'; c.beginPath(); c.arc(px+s*0.32,py+s*0.38,s*0.08,0,Math.PI*2); c.arc(px+s*0.58,py+s*0.38,s*0.08,0,Math.PI*2); c.fill(); c.fillStyle='#111'; c.beginPath(); c.arc(px+s*0.34,py+s*0.4,s*0.04,0,Math.PI*2); c.arc(px+s*0.56,py+s*0.4,s*0.04,0,Math.PI*2); c.fill(); c.strokeStyle='#1d4ed8'; c.lineWidth=3; c.beginPath(); c.arc(px+s*0.45,py+s*0.58,s*0.14,0,Math.PI); c.stroke(); } });
        if(this.over){ c.fillStyle='rgba(0,0,0,.35)'; c.fillRect(0,0,cw,ch); c.fillStyle='#fff'; c.font='700 42px Segoe UI'; c.textAlign='center'; c.fillText('Game Over', cw/2, ch/2); c.textAlign='left'; }
    }
}

class PongApp extends BaseGameApp {
    constructor(rootId, playerNameGetter) { super(rootId, playerNameGetter, { key: 'pong', title: 'Pong', subtitle: 'Classic paddle duel against adaptive AI.' }); if(!this.root)return; this.renderControls(); this.mount(); this.reset(); }
    renderControls(){ this.controlsEl.innerHTML=`<select id="pong-difficulty"><option value="easy">Easy</option><option value="medium" selected>Medium</option><option value="hard">Hard</option></select><button id="pong-start-btn">Start</button>`; this.controlsEl.querySelector('#pong-start-btn').addEventListener('click',()=>this.reset(true)); this.controlsEl.querySelector('#pong-difficulty').addEventListener('change',()=>this.reset(true)); }
    mount(){ this.stageEl.innerHTML=`<canvas class="game-canvas game-canvas-pong" width="900" height="520"></canvas>`; this.canvas=this.stageEl.querySelector('canvas'); this.ctx=this.canvas.getContext('2d'); document.addEventListener('mousemove',e=>{ if(document.getElementById('pong-window')?.style.display==='none') return; const rect=this.canvas.getBoundingClientRect(); const y=((e.clientY-rect.top)/rect.height)*this.canvas.height; this.playerY=Math.max(0,Math.min(this.canvas.height-this.paddleH,y-this.paddleH/2));}); }
    difficultyConfig(){ const diff=this.controlsEl.querySelector('#pong-difficulty')?.value||'medium'; return diff==='easy'?{speed:2.4, reaction:0.065, error:36}:diff==='hard'?{speed:4.3,reaction:0.14,error:10}:{speed:3.2,reaction:0.1,error:20}; }
    reset(start=true){ this.player=0; this.ai=0; this.paddleH=110; this.playerY=205; this.aiY=205; this.aiTargetY=205; this.aiMissBias=0; this.ball={x:450,y:260,vx:4*(Math.random()>.5?1:-1),vy:2}; this.over=false; this.aiCfg=this.difficultyConfig(); this.updateStats(); this.draw(); clearInterval(this.loop); if(start)this.loop=setInterval(()=>this.tick(), 16); }
    chooseAiTarget(){ const miss=(Math.random()*2-1)*this.aiCfg.error; this.aiMissBias=miss; this.aiTargetY=this.ball.y - this.paddleH/2 + miss; }
    tick(){ if(this.over) return; this.ball.x+=this.ball.vx; this.ball.y+=this.ball.vy; if(this.ball.y<12||this.ball.y>this.canvas.height-12) this.ball.vy*=-1; if(this.ball.vx>0 && (this.ball.x>this.canvas.width*0.55)){ if(Math.random()<this.aiCfg.reaction) this.chooseAiTarget(); const delta=this.aiTargetY-this.aiY; if(Math.abs(delta)>2) this.aiY += Math.sign(delta)*Math.min(Math.abs(delta), this.aiCfg.speed); } else { const idle=(this.canvas.height-this.paddleH)/2; const delta=idle-this.aiY; if(Math.abs(delta)>2) this.aiY += Math.sign(delta)*Math.min(Math.abs(delta), this.aiCfg.speed*0.55); }
        this.aiY=Math.max(0,Math.min(this.canvas.height-this.paddleH,this.aiY));
        const hit=(px,py)=> this.ball.x>px&&this.ball.x<px+16&&this.ball.y>py&&this.ball.y<py+this.paddleH; if(hit(30,this.playerY)&&this.ball.vx<0){ this.ball.vx=Math.abs(this.ball.vx)+.25; this.ball.vy=((this.ball.y-(this.playerY+this.paddleH/2))/14); this.chooseAiTarget(); } if(hit(this.canvas.width-46,this.aiY)&&this.ball.vx>0){ this.ball.vx=-(Math.abs(this.ball.vx)+.22); this.ball.vy=((this.ball.y-(this.aiY+this.paddleH/2))/16); }
        if(this.ball.x<0){ this.ai++; this.serve(1); } if(this.ball.x>this.canvas.width){ this.player++; this.serve(-1); }
        if(this.player>=10||this.ai>=10){ this.over=true; clearInterval(this.loop); if(this.player>this.ai){ LeaderboardStore.submit('pong', this.getPlayerName(), this.player, `${this.player}-${this.ai}`); this.renderLeaderboard(); } }
        this.updateStats(); this.draw(); }
    serve(dir){ this.ball={x:450,y:260,vx:4*dir,vy:(Math.random()*4)-2}; this.chooseAiTarget(); }
    updateStats(){ const name=this.controlsEl.querySelector('#pong-difficulty')?.value||'medium'; this.setStats([{label:'Player',value:this.player},{label:'AI',value:this.ai},{label:'Difficulty',value:name[0].toUpperCase()+name.slice(1)},{label:'Race',value:'First to 10'}]); }
    draw(){ const c=this.ctx, cw=this.canvas.width, ch=this.canvas.height; c.fillStyle='#05010d'; c.fillRect(0,0,cw,ch); c.shadowBlur=18; c.shadowColor='#ff3cf7'; c.strokeStyle='#ff4dfb'; c.lineWidth=6; c.strokeRect(12,12,cw-24,ch-24); c.setLineDash([18,16]); c.beginPath(); c.moveTo(cw/2,20); c.lineTo(cw/2,ch-20); c.stroke(); c.setLineDash([]); c.shadowBlur=0; c.fillStyle='#ffd7ff'; c.fillRect(36,this.playerY,12,this.paddleH); c.fillRect(cw-48,this.aiY,12,this.paddleH); c.shadowBlur=12; c.shadowColor='#fff'; c.fillRect(this.ball.x-5,this.ball.y-5,10,10); c.shadowBlur=0; c.font='700 64px Segoe UI'; c.fillStyle='#ffd7ff'; c.fillText(this.player, cw/2-100, 78); c.fillText(this.ai, cw/2+50, 78); if(this.over){ c.fillStyle='rgba(0,0,0,.5)'; c.fillRect(0,0,cw,ch); c.fillStyle='#fff'; c.textAlign='center'; c.font='700 48px Segoe UI'; c.fillText(this.player>this.ai?'Victory':'Defeat', cw/2, ch/2); c.textAlign='left'; } }
}

class FlappyApp extends BaseGameApp {
    constructor(rootId, playerNameGetter) { super(rootId, playerNameGetter, { key: 'flappy', title: 'Flappy Bird', subtitle: 'Tap through pipes and survive the gauntlet.' }); if(!this.root)return; this.renderControls(); this.mount(); this.reset(); }
    renderControls(){ this.controlsEl.innerHTML=`<button id="flappy-start-btn">Start</button><button id="flappy-pause-btn">Pause</button>`; this.controlsEl.querySelector('#flappy-start-btn').addEventListener('click',()=>this.reset(true)); this.controlsEl.querySelector('#flappy-pause-btn').addEventListener('click',()=>this.paused=!this.paused); }
    mount(){ this.stageEl.innerHTML=`<canvas class="game-canvas game-canvas-flappy" width="720" height="520"></canvas>`; this.canvas=this.stageEl.querySelector('canvas'); this.ctx=this.canvas.getContext('2d'); const flap=()=>{ if(document.getElementById('flappy-window')?.style.display==='none') return; if(this.over){ this.reset(true); return; } this.bird.vy=-7.2; }; this.canvas.addEventListener('mousedown', flap); document.addEventListener('keydown', e=>{ if(e.code==='Space'){ e.preventDefault(); flap(); } }); }
    reset(start=true){ this.bird={x:160,y:200,vy:0,r:16}; this.pipes=[]; this.score=0; this.best=Math.max(this.best||0, Number(localStorage.getItem('flappy_best')||0)); this.over=false; this.paused=false; this.spawnTick=0; this.updateStats(); this.draw(); clearInterval(this.loop); if(start)this.loop=setInterval(()=>this.tick(), 16); }
    tick(){ if(this.over||this.paused) return; this.bird.vy += 0.38; this.bird.y += this.bird.vy; this.spawnTick++; if(this.spawnTick>92){ this.spawnTick=0; const gap=145; const top=70+Math.random()*170; this.pipes.push({x:this.canvas.width+70, top, gap, scored:false}); } this.pipes.forEach(p=>p.x -= 3); this.pipes=this.pipes.filter(p=>p.x>-90); for(const p of this.pipes){ if(!p.scored && p.x+64<this.bird.x){ p.scored=true; this.score++; localStorage.setItem('flappy_best', String(Math.max(this.score,this.best||0))); } const hitX=this.bird.x+this.bird.r>p.x && this.bird.x-this.bird.r<p.x+64; const hitY=this.bird.y-this.bird.r<p.top || this.bird.y+this.bird.r>p.top+p.gap; if(hitX&&hitY){ this.end(); return; } } if(this.bird.y<0||this.bird.y>this.canvas.height-52) this.end(); this.updateStats(); this.draw(); }
    end(){ this.over=true; clearInterval(this.loop); this.best=Math.max(this.score,this.best||0); localStorage.setItem('flappy_best', String(this.best)); LeaderboardStore.submit('flappy', this.getPlayerName(), this.score, 'Best score'); this.renderLeaderboard(); this.draw(); }
    updateStats(){ this.setStats([{label:'Score',value:this.score},{label:'Best',value:Math.max(this.best||0,this.score)},{label:'Pipes',value:this.pipes.length},{label:'State',value:this.over?'Down':'Flying'}]); }
    drawBird(x,y){ const c=this.ctx; c.fillStyle='#f6d54a'; c.beginPath(); c.arc(x,y,16,0,Math.PI*2); c.fill(); c.fillStyle='#fff'; c.beginPath(); c.arc(x+4,y-5,4,0,Math.PI*2); c.fill(); c.fillStyle='#111'; c.beginPath(); c.arc(x+5,y-5,2,0,Math.PI*2); c.fill(); c.fillStyle='#f97316'; c.beginPath(); c.moveTo(x+12,y); c.lineTo(x+24,y+4); c.lineTo(x+12,y+8); c.closePath(); c.fill(); c.fillStyle='#ffd84d'; c.beginPath(); c.ellipse(x-3,y+1,8,6,0.4,0,Math.PI*2); c.fill(); }
    draw(){ const c=this.ctx, cw=this.canvas.width, ch=this.canvas.height; const sky=c.createLinearGradient(0,0,0,ch); sky.addColorStop(0,'#87ceeb'); sky.addColorStop(1,'#a9e2ff'); c.fillStyle=sky; c.fillRect(0,0,cw,ch); c.fillStyle='rgba(255,255,255,.35)'; for(let i=0;i<5;i++){ c.beginPath(); c.arc(90+i*130+(Date.now()/60%140),80+(i%2)*26,24,0,Math.PI*2); c.arc(118+i*130+(Date.now()/60%140),80+(i%2)*26,18,0,Math.PI*2); c.arc(72+i*130+(Date.now()/60%140),84+(i%2)*26,18,0,Math.PI*2); c.fill(); }
        this.pipes.forEach(p=>{ c.fillStyle='#1f8c3f'; c.fillRect(p.x,0,64,p.top); c.fillRect(p.x,p.top+p.gap,64,ch-(p.top+p.gap)-50); c.fillStyle='#2dbb57'; c.fillRect(p.x-4,p.top-18,72,18); c.fillRect(p.x-4,p.top+p.gap,72,18); });
        c.fillStyle='#8b5e34'; c.fillRect(0,ch-52,cw,52); c.fillStyle='#62b34e'; c.fillRect(0,ch-56,cw,10); this.drawBird(this.bird.x,this.bird.y); c.fillStyle='rgba(255,255,255,0.8)'; c.font='700 56px Segoe UI'; c.textAlign='center'; c.fillText(this.score, cw/2, 70); if(this.over){ c.fillStyle='rgba(0,0,0,.35)'; c.fillRect(0,0,cw,ch); c.fillStyle='#fff'; c.font='700 46px Segoe UI'; c.fillText('Game Over', cw/2, ch/2); } c.textAlign='left'; }
}