package org.example.factory;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.lang.reflect.InvocationTargetException;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

import org.javatuples.Pair;
import org.reflections.Reflections;

interface HotDrink {
    void consume();
}

class Tea implements HotDrink {
    @Override
    public void consume() {
        System.out.println("Tea es ricardo");
    }
}

class Coffee implements HotDrink {
    @Override
    public void consume() {
        System.out.println("Coffee es ricardo");
    }
}

/**
 * HotDribkn
 */
interface HotDrinkFactory {
    HotDrink prepare(int amount);
}

class TeaFactory implements HotDrinkFactory {

    @Override
    public HotDrink prepare(int amount) {
        System.out.println("        hago algo algo bup bup");
        return new Tea();
    }
}

class CoffeeFactory implements HotDrinkFactory {
    @Override
    public HotDrink prepare(int amount) {
        System.out.println("Hago un cafe gato");
        return new Coffee();
    }
}

class HotDrinkMachine {
    private List<Pair<String, HotDrinkFactory>> namedFactories = new ArrayList<>();

    public HotDrinkMachine() throws InstantiationException, IllegalAccessException, IllegalArgumentException,
            InvocationTargetException, NoSuchMethodException, SecurityException {
        Set<Class<? extends HotDrinkFactory>> types = new Reflections("").getSubTypesOf(HotDrinkFactory.class);
        for (Class<? extends HotDrinkFactory> type : types) {
            namedFactories.add(new Pair<>(
                    type.getSimpleName().replace("Factory", ""),
                    type.getDeclaredConstructor().newInstance()));
        }
    }

    public HotDrink makeDrink() throws Exception {
        System.out.println("Available drinks are:");
        for (int i = 0; i < namedFactories.size(); i++) {
            Pair<String, HotDrinkFactory> item = namedFactories.get(i);
            System.out.println("" + i + ": " + item.getValue0());
        }
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        while (true) {
            String s;
            int i, amount;
            if ((s = reader.readLine()) != null && (i = Integer.parseInt(s)) >= 0
                    && i < namedFactories.size()) {
                System.out.println("Specify amount: ");
                s = reader.readLine();
                if (s != null && (amount = Integer.parseInt(s)) > 0) {
                    return namedFactories.get(i).getValue1().prepare(amount);
                }
            }
            System.out.println("Incorrect input, try again");
        }
    }
}

class DemoFactory {
    public static void main(String[] args) throws Exception {
        HotDrinkMachine machine = new HotDrinkMachine();
        HotDrink drink = machine.makeDrink();
        drink.consume();
    }
}