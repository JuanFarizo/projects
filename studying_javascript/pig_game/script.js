'use strict';

//
let currentPlayer;
let playersScore;
let currentScore;
let playing;

// Element selector
const score0El = document.getElementById('score--0');
const score1El = document.getElementById('score--1');
const scoreElements = [score0El, score1El];
const player0El = document.querySelector('.player--0');
const player1El = document.querySelector('.player--1');
const current0El = document.getElementById('current--0');
const current1El = document.getElementById('current--1');
const currentElements = [current0El, current1El];
const diceEl = document.querySelector('.dice');
const btnNew = document.querySelector('.btn--new');
const btnRoll = document.querySelector('.btn--roll');
const btnHold = document.querySelector('.btn--hold');

// Starting conditions
function init() {
  currentPlayer = 0;
  playersScore = [0, 0];
  currentScore = 0;
  playing = true;
  score0El.textContent = 0;
  score1El.textContent = 0;
  current0El.textContent = 0;
  current1El.textContent = 0;
  diceEl.classList.add('hidden');
  player0El.classList.add('player--active');
  player1El.classList.remove('player--active');
  document.querySelector(`.player--0`).classList.remove('player--winner');
  document.querySelector(`.player--1`).classList.remove('player--winner');
}
init();

// Rolling functionality
btnRoll.addEventListener('click', () => {
  if (playing) {
    let randomNum = Math.trunc(Math.random() * 6) + 1; //1 to 6
    diceEl.classList.remove('hidden');
    diceEl.src = `dice-${randomNum}.png`;

    if (randomNum != 1) {
      currentScore += randomNum;
      currentElements[currentPlayer].textContent = currentScore;
    } else {
      switchPlayer()
    }
  }
});

btnHold.addEventListener('click', () => {
  if (playing) {
    playersScore[currentPlayer] += currentScore;
    scoreElements[currentPlayer].textContent = playersScore[currentPlayer];

    if (playersScore[currentPlayer] >= 100) {
      document.querySelector(`.player--${currentPlayer}`).classList.add('player--winner');
      document.querySelector(`.player--${currentPlayer}`).classList.remove('player--active');
      playing = false;
    }

    switchPlayer();
  }
});

function switchPlayer() {
  currentElements[currentPlayer].textContent = 0;
  currentPlayer ^= 1;
  player0El.classList.toggle('player--active');
  player1El.classList.toggle('player--active');
  currentScore = 0;
}

btnNew.addEventListener('click', init);