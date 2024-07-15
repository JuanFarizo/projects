'use strict'

let secretNumber;
let score = 20;
let hide = true;
let highScore = 0;

document.querySelector('.startbtn').addEventListener('click', startGame);

document.querySelector('.show').addEventListener('click', () => {
    if (hide) {
        let butt = document.querySelector('.titulo');
        butt.textContent = secretNumber;
        document.querySelector('.show').textContent = 'Hide';
        hide = false;
    } else {
        let butt = document.querySelector('.titulo');
        butt.textContent = 'Numero Secreto';
        document.querySelector('.show').textContent = 'Show Number';
        hide = true;
    }

});

function startGame() {
    setScoreAndSecretNumber();
    document.querySelector('.score').textContent = score;
}

function setScoreAndSecretNumber() {
    secretNumber = Math.trunc(Math.random() * 20) + 1;
    score = 20;
}


document.querySelector('.again').addEventListener('click', again);

function again() {
    setScoreAndSecretNumber();
    clearnAndHideValue();
}

function clearnAndHideValue() {
    document.querySelector('.show').textContent = 'Show Number';
    document.querySelector('.titulo').textContent = 'Numero Secreto'
    document.querySelector('body').style.backgroundColor = 'white';
    document.querySelector('.score').textContent = score;
    document.querySelector('.inputNum').value = '';
}

document.querySelector('.check').addEventListener('click', function () {
    const guess = Number(document.querySelector('.inputNum').value);
    console.log(Number.isNaN(guess));
    if (Number.isNaN(guess)) { document.querySelector('.help').textContent = 'No es un numero sos pajerito o te haces'; }
    else {
        if (score) {
            document.querySelector('.help').textContent = 'perdiste topu';
            if (guess === secretNumber) {
                document.querySelector('.help').textContent = 'Bien gato adivinaste';
                document.querySelector('body').style.backgroundColor = '#60b347';
                document.querySelector('.inputNum').style.width = '30rem';
                if (score > highScore) {
                    highScore = score;
                    document.querySelector('.highscore').textContent = highScore;
                }
            } else if (guess < secretNumber) {
                --score;
                document.querySelector('.score').textContent = score;
                document.querySelector('.help').textContent = 'Tira, tira para arriba tira';
            } else {
                --score;
                document.querySelector('.score').textContent = score;
                document.querySelector('.help').textContent = 'Tas pa abajo';
            }
        }
        else {
            document.querySelector('.help').textContent = 'perdiste topu';
            document.querySelector('body').style.backgroundColor = 'red';
            document.querySelector('.check').setAttribute('disabled', true);
        }
    }

});