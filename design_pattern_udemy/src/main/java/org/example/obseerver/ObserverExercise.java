package org.example.obseerver;
import java.io.Closeable;
import java.io.IOException;

//---Observable Coding Exercise---
//Imagine a game where one or more rats can attack a player.
//Each individual rat has an attack  value of 1. However,
//rats attack as a swarm, so each rat's attack  value is equal
//to the total number of rats in play.
//
//Given that a rat enters play through the constructor and leaves play (dies)
//via its close()  method, please implement the Game and Rat classes so that,
//at any point in the game, the attack  value of a rat is always consistent.

class GameObExe
{
    // todo
}

class Rat implements Closeable
{
    private GameObExe game;
    public int attack = 1;

    public Rat(GameObExe game)
    {
        // todo: rat enters game here
    }

    @Override
    public void close() throws IOException
    {
        // todo: rat dies ;(
    }
}

public class ObserverExercise {
    public static void main(String[] args) {

    }
}
