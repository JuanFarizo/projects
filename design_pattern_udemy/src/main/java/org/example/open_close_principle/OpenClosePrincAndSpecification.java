package org.example.open_close_principle;

import java.util.List;
import java.util.stream.Stream;

//Specification is an enterprise pattern
public class OpenClosePrincAndSpecification {

    enum Color {
        RED, GREEN, BLUE
    }

    enum Size {
        SMALL, MEDIUM, LARGE, YUGE
    }

    static class Product {
        public String name;
        public Color color;
        public Size size;

        public Product(String name, Color color, Size size) {
            this.name = name;
            this.color = color;
            this.size = size;
        }
    }

    static class ProductFilter {
        public Stream<Product> filterByColor(List<Product> products,
                                             Color color) {
            return products.stream().filter(p -> color.equals(p.color));
        }

        public Stream<Product> filterBySize(List<Product> products,
                                            Size size) {
            return products.stream().filter(p -> size.equals(p.size));
        }
    }

    interface Specification<T> {
        boolean isSatisfied(T item);
    }
    interface Filter<T> {
        Stream<T> filter(List<T> items, Specification<T> spec);
    }

    static class ColorSpecification implements Specification<Product> {
        private final Color color;

        public ColorSpecification(Color color) {
            this.color = color;
        }

        @Override
        public boolean isSatisfied(Product item) {
            return this.color.equals(item.color);
        }
    }


    static class SizeSpecification implements Specification<Product> {
        private  final Size size;

        public SizeSpecification(Size size) {
            this.size =  size;
        }

        @Override
        public boolean isSatisfied(Product item) {
            return this.size.equals(item.size);
        }
    }

    static class BetterFilter implements Filter<Product> {

        @Override
        public Stream<Product> filter(List<Product> items, Specification<Product> spec) {
            return items.stream().filter(spec::isSatisfied);
        }
    }

    static class AndSpecification<T> implements Specification<T> {
        private final Specification<T> first, second;

        public AndSpecification(Specification<T> first, Specification<T> second) {
            this.first = first;
            this.second = second;
        }

        @Override
        public boolean isSatisfied(T item) {
            return first.isSatisfied(item) && second.isSatisfied(item);
        }
    }


    static class Demo {
        public static void main(String[] args) {
            Product apple = new Product("Apple", Color.GREEN, Size.SMALL);
            Product tree = new Product("Tree", Color.GREEN, Size.LARGE);
            Product house = new Product("House", Color.BLUE, Size.LARGE);

            List<Product> products = List.of(apple, tree, house);

           ProductFilter pf = new ProductFilter();
            System.out.println("Green Products (old):  ");
            pf.filterByColor(products, Color.GREEN)
                    .forEach(p -> System.out.println(" - " + p.name + " is green"));

            BetterFilter bf = new BetterFilter();
            System.out.println("Green Products (new):  ");
            bf.filter(products, new ColorSpecification(Color.GREEN))
                    .forEach(p -> System.out.println(" - " + p.name + " is green!"));

            System.out.println("Large blue items: ");
            bf.filter(products, new AndSpecification<>(
                    new ColorSpecification(Color.GREEN),
                    new SizeSpecification(Size.LARGE)
            )).forEach(p -> System.out.println(" - " + p.name + " is green!" + " color: " + p.color + " size: " + p.size));

        }
    }


}

