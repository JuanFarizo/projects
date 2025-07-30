import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

class HandshakeCalculator {
        /*
        00001 = wink
        00010 = double blink
        00100 = close your eyes
        01000 = jump
        10000 = Reverse the order of the operations in the secret handshake.
        */
    Map<Integer, Signal> signals = new HashMap<Integer, Signal>() {{
        put(1, Signal.WINK);
        put(2, Signal.DOUBLE_BLINK);
        put(4, Signal.CLOSE_YOUR_EYES);
        put(8, Signal.JUMP);
        put(16, Signal.REVERSE);
    }};

    List<Signal> calculateHandshake(int number) {
    List<Signal> result = new ArrayList<>();
//          valor:   11010
//        & mascara: 01000
//          ----------------
//                   01000
        for (int i = 0; i < 5; i++) {
            int mascara = 1 << i;
            int binaryPosition = (number & mascara);
            if(signals.containsKey(binaryPosition)) {
                result.add(signals.get(binaryPosition));
            }
        }
        if (result.remove(Signal.REVERSE)) {
            Collections.reverse(result);
        }
        return result;
    }

}
