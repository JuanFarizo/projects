package org.example.state;
// This is an old approach of how to implement state
// Is the example for gang of four, the modern approach is the StateMachine
class State {
    void on(LightSwitch ls) {
        System.out.println("Light is already on");
    }

    void off(LightSwitch ls) {
        //So when they're in the off state, and they try to switch off the light,
        // we should end up here because
        //there's going to be no corresponding override in the off state itself.
        System.out.println("Light is already off");
    }
}

class OnState extends State {
    public OnState() {
        System.out.println("Light turned on");
    }

    // it's a bit of a bizarre situation because we have the
    // state changing a reference in the owner of
    // the state to a different state.
    @Override
    void off(LightSwitch ls) {
        System.out.println("Switching light off..");
        ls.setState(new OffState());
    }
}

class OffState extends State {
    public OffState() {
        System.out.println("Light turned off");
    }

    // it's a bit of a bizarre situation because we have the
    // state changing a reference in the owner of
    // the state to a different state.
    void om(LightSwitch ls) {
        System.out.println("Switching light on..");
        ls.setState(new OnState());
    }
}

class LightSwitch {
    private State state;

    public LightSwitch() {
        state = new OffState();
    }

    public void setState(State state) {
        this.state = state;
    }

    void on() {
        state.on(this);
    }

    void off() {
        state.off(this);
    }
}

public class StateDemo {
    public static void main(String[] args) {

    }
}
