package restricted.classes.instantiation.init;

import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationTargetException;
import java.util.ArrayList;
import java.util.List;

import restricted.classes.instantiation.game.Game;
import restricted.classes.instantiation.game.internal.TicTacToeGame;

public class Main {
    public static void main(String[] args)
            throws InstantiationException, IllegalAccessException, IllegalArgumentException, InvocationTargetException {
        Game game = createObjectRecursively(TicTacToeGame.class);
        game.startGame();
    }

    public static <T> T createObjectRecursively(Class<T> clazz)
            throws InstantiationException, IllegalAccessException, IllegalArgumentException, InvocationTargetException {
        Constructor<?> constructor = getFirstConstructor(clazz);
        List<Object> constructorArguments = new ArrayList<>();

        for (Class<?> argumetType : constructor.getParameterTypes()) {
            Object argumentValue = createObjectRecursively(argumetType);
            constructorArguments.add(argumentValue);
        }

        constructor.setAccessible(true);
        return (T) constructor.newInstance(constructorArguments.toArray());
    }

    public static Constructor<?> getFirstConstructor(Class<?> clazz) {
        Constructor<?>[] constructors = clazz.getDeclaredConstructors();
        if (constructors.length == 0) {
            throw new IllegalStateException(
                    String.format("No constructor has been found for class %s", clazz.getName()));
        }
        return constructors[0];
    }
}
