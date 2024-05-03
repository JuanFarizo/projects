package org.example.state;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.javatuples.Pair;

enum StateMD {
    OFF_HOOK, //Starting
    ON_HOOK, //Terminal
    CONNECTING, //Transitions
    CONNECTED,
    ON_HOLD
}

enum TriggerMD {
    CALL_DIALED,
    HUNG_UP,
    CALL_CONNECTED,
    PLACE_ON_HOLD,
    TAKEN_OFF_HOLD,
    LEFT_MESSAGE,
    STOP_USING_PHONE
}

public class StateMachineDemo {
    private static final Map<StateMD, List<Pair<TriggerMD, StateMD>>> rules = new HashMap<>();

    //map which specifies that for any given state there is a list
    // of possible transitions and their associated states.
    static {
        rules.put(StateMD.OFF_HOOK, List.of(
                new Pair<>(TriggerMD.CALL_DIALED, StateMD.CONNECTING),
                new Pair<>(TriggerMD.STOP_USING_PHONE, StateMD.ON_HOOK)
        ));
        rules.put(StateMD.CONNECTING, List.of(
                new Pair<>(TriggerMD.HUNG_UP, StateMD.OFF_HOOK),
                new Pair<>(TriggerMD.CALL_CONNECTED, StateMD.CONNECTED)
        ));
        rules.put(StateMD.CONNECTED, List.of(
                new Pair<>(TriggerMD.LEFT_MESSAGE, StateMD.OFF_HOOK),
                new Pair<>(TriggerMD.HUNG_UP, StateMD.OFF_HOOK),
                new Pair<>(TriggerMD.PLACE_ON_HOLD, StateMD.ON_HOLD)
        ));
        rules.put(StateMD.ON_HOLD, List.of(
                new Pair<>(TriggerMD.TAKEN_OFF_HOLD, StateMD.CONNECTED),
                new Pair<>(TriggerMD.HUNG_UP, StateMD.OFF_HOOK)
        ));
    }

    private static StateMD currentState = StateMD.OFF_HOOK;
    private static final StateMD exitState = StateMD.ON_HOOK;

    public static void main(String[] args) throws IOException {
        BufferedReader console = new BufferedReader(
                new InputStreamReader(System.in));

        while (true) {
            System.out.println("The phone is currently " + currentState);
            System.out.println("Select a trigger: ");
            for (int i = 0; i < rules.get(currentState).size(); i++) {
                TriggerMD trigger = rules.get(currentState).get(i).getValue0();
                System.out.println(" " + i + ". " + trigger);
            }
            boolean parseOK;
            int choice = 0;
            do {
                try {
                    System.out.println("Please enter your choice: ");
                    choice = Integer.parseInt(console.readLine());
                    parseOK = choice >= 0 &&
                            choice < rules.get(currentState).size();
                } catch (Exception e) {
                    parseOK = false;
                }
            } while (!parseOK);
            currentState = rules.get(currentState).get(choice).getValue1();
            if (currentState == exitState)
                break;
        }
        System.out.println("And we are done");
    }
}
