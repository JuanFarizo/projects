package demo;

import org.apache.commons.codec.binary.Hex;
import org.apache.commons.logging.LogFactory;

// Library navigation fixture (check 95): three kinds of library class.
//   LogFactory : commons-logging 1.2, a -sources.jar is in ~/.m2 -> real source.
//   Hex        : commons-codec 1.20.0, no sources jar -> Fernflower (jdt.ls's bundled decompiler).
//   sortedBy   : kotlin-stdlib 2.4.10 (no sources jar), declared in SequencesKt___SequencesKt, whose body Fernflower
//                cannot decompile (`// $FF: Couldn't be decompiled`) -> Nv4J's CFR backup replaces the buffer.
public class App {
    public static void main(String[] a) {
        LogFactory.getLog(App.class).info("x");
        System.out.println(Hex.encodeHexString(new byte[] {1}));
        kotlin.sequences.Sequence<String> s = kotlin.sequences.SequencesKt.sequenceOf("b", "a");
        System.out.println(kotlin.sequences.SequencesKt.sortedBy(s, x -> x));
    }
}
