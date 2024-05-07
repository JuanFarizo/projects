package org.example.strategy;

import java.util.List;
import java.util.function.Supplier;

enum OutputFormSt {
    MARKDOWN, HTML
}

interface ListStrategy {
    default void start(StringBuilder sb) {
    }

    void addListItem(StringBuilder sb, String item);

    default void end(StringBuilder sb) {
    }//Because for markdown we don't need start and end so the default is an empty body
}

class MarkDownListStrategy implements ListStrategy {

    @Override
    public void addListItem(StringBuilder sb, String item) {
        sb.append(" * ").append(item)
                .append(System.lineSeparator());
    }
}

class HtmlListStrategy implements ListStrategy {

    @Override
    public void start(StringBuilder sb) {
        sb.append("<ul>").append(System.lineSeparator());
    }

    @Override
    public void addListItem(StringBuilder sb, String item) {
        sb.append("<li>")
                .append(item)
                .append("</li>")
                .append(System.lineSeparator());
    }

    @Override
    public void end(StringBuilder sb) {
        sb.append("</ul>").append(System.lineSeparator());
    }
}

class TextProcessorStaticSt<LS extends ListStrategy> {
    private StringBuilder sb = new StringBuilder();
    private LS listStrategy;

    public TextProcessorStaticSt(
            Supplier<? extends LS> supplier) { //would need to specify some sort of lambda function which returns something which extends this list strategy type that you're after.
        this.listStrategy = supplier.get();
    }

    public void appendList(List<String> items) {
        // This is the place where you can employ the strategy and add the appropriate elements to the StringBuilder.
        listStrategy.start(sb);
        for (String item : items) {
            listStrategy.addListItem(sb, item);
        }
        listStrategy.end(sb);
    }

    @Override
    public String toString() {
        return sb.toString();
    }
}

class TextProcessorDynamicSt {
    private StringBuilder sb = new StringBuilder();
    private ListStrategy listStrategy;

    public TextProcessorDynamicSt(OutputFormSt format) {
        setOutPutFormat(format);
    }

    public void setOutPutFormat(
            OutputFormSt format) {//Dynamic Strategy because we can change it at run time
        switch (format) {
            case MARKDOWN -> listStrategy = new MarkDownListStrategy();
            case HTML -> listStrategy = new HtmlListStrategy();
        }
    }

    public void appendList(List<String> items) {
        // This is the place where you can employ the strategy and add the appropriate elements to the StringBuilder.
        listStrategy.start(sb);
        for (String item : items) {
            listStrategy.addListItem(sb, item);
        }
        listStrategy.end(sb);
    }

    public void clear() {
        sb.setLength(0);
    }

    @Override
    public String toString() {
        return sb.toString();
    }
}

public class StrategyDemo {
    public static void main(String[] args) {
        TextProcessorDynamicSt tpDynamic = new TextProcessorDynamicSt(
                OutputFormSt.MARKDOWN);
        tpDynamic.appendList(List.of("liberate", "egalite", "fraternite"));
        System.out.println(tpDynamic);
        tpDynamic.clear();

        tpDynamic.setOutPutFormat(OutputFormSt.HTML);
        tpDynamic.appendList(
                List.of("inheritance", "encapsulation", "polymorphism"));
        System.out.println(tpDynamic);

        TextProcessorStaticSt<HtmlListStrategy> tpStatic = new TextProcessorStaticSt<>(HtmlListStrategy::new);
        tpStatic.appendList(List.of("liberate", "egalite", "fraternite"));
        System.out.println(tpStatic);
    }
}
