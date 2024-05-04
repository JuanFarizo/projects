package org.example.state;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.javatuples.Pair;

class CombinationLock {
    private int[] combination;
    public String status;
    private StateEx currentStatus;
    private static final Map<StateEx, List<Pair<TriggerEx, StateEx>>> rules
            = new HashMap<>();

    static {
        rules.put(StateEx.LOCKED, List.of(
                new Pair<>(TriggerEx.ENTER_DIGIT, StateEx.WAITING_DIGIT)));
        rules.put(StateEx.WAITING_DIGIT, List.of(
                new Pair<>(TriggerEx.STOP_ENTERING_DIGIT, StateEx.OPEN),
                new Pair<>(TriggerEx.STOP_ENTERING_DIGIT, StateEx.ERROR)));
    }

    public CombinationLock(int[] combination) {
        this.combination = combination;
        status = StateEx.LOCKED.toString();
        currentStatus = StateEx.LOCKED;
    }

    public void enterDigit(int digit) {
        if (StateEx.LOCKED.equals(currentStatus)) {
            currentStatus = rules.get(currentStatus).getFirst().getValue1();
            status  = "";
        }
        if (StateEx.WAITING_DIGIT.equals(currentStatus)) {
            status += digit;
            if (status.length() == combination.length) {
                if (isCombinationCorrect()) {
                    status = StateEx.OPEN.toString();
                    currentStatus = StateEx.OPEN;
                } else {
                    status = StateEx.ERROR.toString();
                    currentStatus = StateEx.ERROR;
                }
            }
        }
    }

    private boolean isCombinationCorrect() {
        boolean result = true;
        char[] charArray = status.toCharArray();
        for (int i = 0; i < charArray.length; i++) {
            if (combination[i] != charArray[i] - '0')
                return false;
        }
        return result;
    }
}

enum StateEx {
    LOCKED,
    OPEN,
    ERROR,
    WAITING_DIGIT
}

enum TriggerEx {
    ENTER_DIGIT,
    STOP_ENTERING_DIGIT
}

public class StateExercise {
    public static void main(String[] args) {
        CombinationLock cl = new CombinationLock(new int[] { 1, 2, 3, 4 });
        System.out.println(cl.status);
        cl.enterDigit(1);
        System.out.println(cl.status);
        cl.enterDigit(2);
        System.out.println(cl.status);
        cl.enterDigit(3);
        System.out.println(cl.status);
        cl.enterDigit(4);
        System.out.println(cl.status);

    }
}
