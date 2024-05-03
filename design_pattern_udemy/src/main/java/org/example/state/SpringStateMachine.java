package org.example.state;

import java.util.EnumSet;
import org.springframework.statemachine.StateMachine;
import org.springframework.statemachine.config.StateMachineBuilder;

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

        return builder.build();
    }
    public static void main(String[] args) {

    }
}
