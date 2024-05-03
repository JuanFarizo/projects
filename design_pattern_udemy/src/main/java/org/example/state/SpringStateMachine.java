package org.example.state;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.EnumSet;
import java.util.List;
import java.util.stream.Collectors;
import org.springframework.statemachine.StateMachine;
import org.springframework.statemachine.config.StateMachineBuilder;
import org.springframework.statemachine.state.State;
import org.springframework.statemachine.transition.Transition;

enum StateSSM {
    OFF_HOOK, //Starting
    ON_HOOK, //Terminal
    CONNECTING, //Transitions
    CONNECTED,
    ON_HOLD
}

enum EventsSSM {
    CALL_DIALED,
    HUNG_UP,
    CALL_CONNECTED,
    PLACE_ON_HOLD,
    TAKEN_OFF_HOLD,
    LEFT_MESSAGE,
    STOP_USING_PHONE
}

public class SpringStateMachine {
    public static StateMachine<StateSSM, EventsSSM> buildMachine() throws Exception {
        StateMachineBuilder.Builder<StateSSM, EventsSSM> builder
                = StateMachineBuilder.builder();

        builder.configureStates()
                .withStates()
                .initial(StateSSM.OFF_HOOK)
                .states(EnumSet.allOf(StateSSM.class));

        builder.configureTransitions()
                .withExternal()
                .source(StateSSM.OFF_HOOK)
                .event(EventsSSM.CALL_DIALED)
                .target(StateSSM.CONNECTING)
                .and()
                .withExternal()
                .source(StateSSM.OFF_HOOK)
                .event(EventsSSM.STOP_USING_PHONE)
                .target(StateSSM.ON_HOOK)
                .and()
                .withExternal()
                .source(StateSSM.CONNECTING)
                .event(EventsSSM.HUNG_UP)
                .target(StateSSM.OFF_HOOK)
                .and()
                .withExternal()
                .source(StateSSM.CONNECTING)
                .event(EventsSSM.CALL_CONNECTED)
                .target(StateSSM.CONNECTED)
                .and()
                .withExternal()
                .source(StateSSM.CONNECTED)
                .event(EventsSSM.LEFT_MESSAGE)
                .target(StateSSM.OFF_HOOK)
                .and()
                .withExternal()
                .source(StateSSM.CONNECTED)
                .event(EventsSSM.HUNG_UP)
                .target(StateSSM.OFF_HOOK)
                .and()
                .withExternal()
                .source(StateSSM.CONNECTED)
                .event(EventsSSM.PLACE_ON_HOLD)
                .target(StateSSM.OFF_HOOK)
                .and()
                .withExternal()
                .source(StateSSM.ON_HOLD)
                .event(EventsSSM.TAKEN_OFF_HOLD)
                .target(StateSSM.CONNECTED)
                .and()
                .withExternal()
                .source(StateSSM.ON_HOLD)
                .event(EventsSSM.HUNG_UP)
                .target(StateSSM.OFF_HOOK);

        return builder.build();
    }

    public static void main(String[] args) throws Exception {
        StateMachine<StateSSM, EventsSSM> machine = buildMachine();
        machine.start();

        StateSSM exitState = StateSSM.ON_HOOK;

        BufferedReader console = new BufferedReader(
                new InputStreamReader(System.in));
        while (true)
        {
            State<StateSSM, EventsSSM> state = machine.getState();

            System.out.println("The phone is currently " + state.getId());
            System.out.println("Select a trigger:");

            List<Transition<StateSSM, EventsSSM>> ts = machine.getTransitions()
                    .stream()
                    .filter(t -> t.getSource() == state)
                    .toList();
            for (int i = 0; i < ts.size(); ++i)
            {
                System.out.println(" " + i + ". " +
                        ts.get(i).getTrigger().getEvent());
            }

            boolean parseOK;
            int choice = 0;
            do
            {
                try
                {
                    System.out.println("Please enter your choice:");

                    choice = Integer.parseInt(console.readLine());
                    parseOK = choice >= 0 && choice < ts.size();
                }
                catch (Exception e)
                {
                    parseOK = false;
                }
            } while (!parseOK);

            // perform the transition
            machine.sendEvent(ts.get(choice).getTrigger().getEvent());

            if (machine.getState().getId() == exitState)
                break;
        }
        System.out.println("And we are done!");
    }

}

