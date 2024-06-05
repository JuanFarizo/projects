window.addEventListener("load", function () {
  const canvas = document.getElementById("canvas1");

  const ctx = canvas.getContext("2d");
  canvas.width = 500;
  canvas.height = 500;

  class inputHandler {
    constructor(game) {
      this.game = game;
      window.addEventListener("keydown", (e) => {
        if ((e.key === "ArrowUp" || e.key === "ArrowDown") && this.game.keys.indexOf(e.key) === -1) {
          this.game.keys.push(e.key);
        } else if (e.key === " ") {
          this.game.player.shootTop();
        }
      });
      window.addEventListener("keyup", (e) => {
        if (this.game.keys.indexOf(e.key) > -1) {
          this.game.keys.splice(this.game.keys.indexOf(e.key), 1);
        }
      });
    }
  }
  class Projectile {
    constructor(game, x, y) {
      this.game = game;
      this.x = x;
      this.y = y;
      this.width = 10;
      this.height = 3;
      this.speed = 3;
      this.markedForDeletion = false;
    }
    update() {
      this.x += this.speed;
      if (this.x > this.game.width * 0.8) this.markedForDeletion = true;
    }
    draw(context) {
      context.fillStyle = "yellow";
      context.fillRect(this.x, this.y, this.width, this.height);
    }
  }
  class Particle {}
  class Player {
    constructor(game) {
      this.game = game;
      this.width = 120;
      this.height = 190;
      this.x = 20;
      this.y = 100;
      this.speedY = 0;
      this.speedX = 0;
      this.projectiles = [];
    }
    update() {
      if (this.game.keys.includes("ArrowUp")) this.speedY = -this.maxSpeed;
      else if (this.game.keys.includes("ArrowDown"))
        this.speedY = this.maxSpeed;
      else this.speedY = 0;
      this.y += this.speedY;
      this.x += this.speedX;
      this.maxSpeed = 2;
      // Handle Projectiles
      this.projectiles.forEach((p) => {
        p.update();
      });
      this.projectiles = this.projectiles.filter((p) => !p.markedForDeletion);
    }
    draw(context) {
      context.fillStyle = "black";
      context.fillRect(this.x, this.y, this.width, this.height);
      this.projectiles.forEach(p => {
        p.draw(context);
      });
    }
    shootTop() {
      if(this.game.ammo > 0) {
        this.projectiles.push(new Projectile(this.game, this.x, this.y));
        this.game.ammo--;
      }
    }
  }
  class Enemy {
    constructor(game) {
      this.game = game;
      this.x = this.game.width;
      this.speedX =  Math.random() * -1.5 - 0.5;
      this.markedForDeletion = false;
      this.lives = 5;
      this.score = this.lives;
    }
    update() {
      this.x += this.speedX;
      if(this.x + this.width < 0) this.markedForDeletion = true;
    }
    draw(context) {
      context.fillStyle = 'red';
      context.fillRect(this.x, this.y, this.width, this.height);
      context.font = "20px Helvetica"
      context.fillText(this.lives, this.x, this.y);
    }
  }
  class Layer {
    constructor(game, image, speedModifier) {
      this.game = game;
      this.image = image;
      this.speedModifier = speedModifier;
      this.width = 1768;
      this.height = 500;
      this.x = 0;
      this.y = 0;
    }
    update() {
      if(this.x <= -this.width) this.x  = 0;
      else this.x -= this.game.speed * this.speedModifier;
    }
    draw(context) {
      context.drawImage(this.image, this.x, this.y);
    }
  }
  class Background {
    constructor(game) {
      this.game = game;
      this.image1 = document.getElementByI('layer1');
      this.layer1 = new Layer(game, image1, 1);
      this.layers = [];
    }
    update() {

    }
    draw() {

    }
  }
  class UI {
    constructor(game) {
      this.game = game;
      this.fontSize = 25;
      this.fontFamily = "Helvetica";
      this.color = "white";
    }
    draw(context) {
      context.save();
      //Score
      context.fillStyle = this.color;
      context.shadowOffsetX = 2;
      context.shaddowOffsetY = 2;
      context.shadowColor = "black"
      context.font = this.fontSize + "px " + this.fontFamily;
      context.fillText("Score: " + this.game.score, 20, 40);

      //Ammo 
      for (let i = 0; i < this.game.ammo; i++) {
        context.fillRect(20 + 5 * i, 50, 3, 20);
      }

      //Timer
      const formatteTime = (this.game.gameTime * 0.001).toFixed(1);
      context.fillText("Timer:" + formatteTime, 20, 100)
      // Game over Message
      if(this.game.gameOver) {
        context.textAlign = "center";
        let message1;
        let message2;
        if(this.game.score > this.game.winningScore) {
          message1 = "You win";
          message2 = "Well done!";
        } else {
          message1 = "You lose!";
          message2 = "Try again next time!"
        }
        context.font = "50px "+ this.fontFamily;
        context.fillText(message1, this.game.width * 0.5, this.game.height * 0.5);
        context.font = "25px "+ this.fontFamily;
        context.fillText(message2, this.game.width * 0.5, this.game.height * 0.5 + 40);
      }
      context.restore(); // Restore the most recent canvas state
    }
  }
  class Angler1 extends Enemy {
    constructor(game) {
      super(game);
      this.width = 228 * 0.2;
      this.height = 169 * 0.2;
      this.y = Math.random() * (this.game.height * 0.9 - this.height);
    }
  }
  class Game {
    constructor(width, height) {
      this.width = width;
      this.height = height;
      this.player = new Player(this);
      this.input = new inputHandler(this);
      this.ui = new UI(this);
      this.keys = [];
      this.enemies = [];
      this.enemyTimer = 0;
      this.enemyInter = 1000;
      this.ammo = 20;
      this.maxAmmo = 50;
      this.ammoTimer = 0;
      this.ammoInterval = 500;
      this.gameOver = false;
      this.score = 0;
      this.winningScore = 10;
      this.gameTime = 0;
      this.timeLimit = 5000;
      this.speed = 1;
    }
    update(deltaTime) {
      if(!this.gameOver) this.gameTime += deltaTime;
      if(this.gameTime > this.timeLimit) this.gameOver = true;
      this.player.update();
      if(this.ammoTimer > this.ammoInterval) {
        if(this.ammo < this.maxAmmo) this.ammo++;
        this.ammoTimer = 0;
      } else {
        this.ammoTimer += deltaTime;
      }
      this.enemies.forEach(e => {
        e.update();
        if(this.checkCollition(this.player, e)) {
          e.markedForDeletion = true;
        }
        this.player.projectiles.forEach(p => {
          if(this.checkCollition(p, e)) {
            e.lives--;
            p.markedForDeletion = true;
            if(e.lives  <= 0) {
              e.markedForDeletion = true;
              if(!this.gameOver)
              this.score += e.score;
              if(this.score > this.winningScore) {
                this.gameOver = true;
              }
            }
          }
        })
      });
      this.enemies = this.enemies.filter(e => !e.markedForDeletion);
      if(this.enemyTimer > this.enemyInter && !this.gameOver) {
          this.addEnemy();
          this.enemyTimer = 0;
      } else {
        this.enemyTimer += deltaTime;
      }
    }
    draw(context) {
      this.player.draw(context);
      this.ui.draw(context);
      this.enemies.forEach(e => {
        e.draw(context);
      })
    }
    addEnemy() {
      this.enemies.push(new Angler1(this));
    }
    checkCollition(rect1, rect2) {
      return (
        rect1.x < rect2.x + rect2.width &&
        rect1.x + rect1.width > rect2.x &&
        rect1.y < rect2.y + rect2.height &&
        rect1.height + rect1.y > rect2.y
      );
    }
  }

  const game = new Game(canvas.width, canvas.height);
  let lastTime = 0;
  // Animation Loop
  function animate(timeStam) {
    const deltaTime = timeStam - lastTime;
    lastTime = timeStam;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    game.update(deltaTime);
    game.draw(ctx);
    requestAnimationFrame(animate); // Tells the browser that we wish to perform an animation and it requests that the browser calls a specified function to update an animation before next repaint
  }
  animate(0);
});