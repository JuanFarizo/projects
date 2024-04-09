'use strict'

const secretNumber = Math.trunc(Math.random()*20)+1;

let score = 2;

document.querySelector('.startbtn').addEventListener('click', () => {
    document.querySelector('.titulo').textContent = secretNumber;
});


let scoreTextContent = document.querySelector('.score').textContent;

document.querySelector('.check').addEventListener('click', function () {
    const guess = Number(document.querySelector('.inputNum').value);
    if(score) {

        document.querySelector('.help').textContent = 'perdiste topu';
    
        if(guess === secretNumber) {
            document.querySelector('.help').textContent = 'Bien gato adivinaste';
        } else if(guess < secretNumber) {
            scoreTextContent = --score;
            document.querySelector('.help').textContent = 'Tira, tira para arriba tira';
        } else {
            scoreTextContent = --score;
            document.querySelector('.help').textContent = 'Tas pa abajo';
        }
    }
        if(!score) { 
            document.querySelector('.help').textContent = 'perdiste topu';
            document.querySelector('.check').setAttribute('disabled', true);
        }
});