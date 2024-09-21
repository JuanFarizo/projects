package fields;

import java.lang.reflect.Field;

public class Introduction {

    public static void main(String[] args)
            throws IllegalArgumentException, IllegalAccessException, NoSuchFieldException, SecurityException {
        printDeclaredFieldsInfo(Movie.class, new Movie("Rambo", 1984, true, Category.ACTION, 99));
        Field staticField = Movie.class.getDeclaredField("MINIMUM_PRICE");
        Object object = staticField.get(null);
        System.out.println(object);

    }

    public static <T> void printDeclaredFieldsInfo(Class<? extends T> clazz, T instance)
            throws IllegalArgumentException, IllegalAccessException {
        for (Field field : clazz.getDeclaredFields()) {
            System.out.println(
                    String.format(
                            "Field name: %s type %s",
                            field.getName(),
                            field.getType().getName()));

            System.out.println(
                    String.format("This field is synthetic %s", field.isSynthetic()));
            System.out.println(
                    String.format("Field value is: %s", field.get(instance)));
            System.out.println();
        }
    }

    public static class Movie extends Product {
        public static final double MINIMUM_PRICE = 10.99;
        private boolean isReleased;
        private Category category;
        private double actualPrice;

        public Movie(String name, int year, boolean isReleased, Category category, double price) {
            super(name, year);
            this.isReleased = isReleased;
            this.category = category;
            this.actualPrice = Math.max(price, MINIMUM_PRICE);
        }

        // Nested class
        public class MovieStats {
            private double timeWatched;

            public MovieStats(double timeWatched) {
                this.timeWatched = timeWatched;
            }

            // notice that the nested non-static class movie stats has access to the actual
            // price variable defined in the parent movie class that indicates to us that
            // the movie stats class has some kind of link to the instance of the movie
            // class but we don't see it explicitly
            public double getRevenue() {
                return timeWatched * actualPrice;
            }
        }

    }

    public static class Product {
        protected String name;
        protected int year;
        protected double actualPrice;

        public Product(String name, int year) {
            this.name = name;
            this.year = year;
        }
    }

    public enum Category {
        AVENTURE,
        ACTION,
        COMEDY
    }
}
